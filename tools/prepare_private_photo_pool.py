"""Prepare private display assets without changing the supplied archive.

Uses ZIP CRC32, lengths, image decoding, and direct byte comparison.
The output stays outside the public source export; originals remain in ZIP.
"""
import argparse
import io
import json
import pathlib
import re
import stat
import zipfile
import zlib

from PIL import Image, ImageCms, ImageOps


def natural_key(name):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r'(\d+)', name)]


def readable_name(info):
    if info.flag_bits & 0x800:
        return info.filename
    try:
        return info.filename.encode('cp437').decode('gb18030')
    except (UnicodeError, LookupError):
        return info.filename


def prepare(archive, output, edge=2048, quality=82):
    archive, output = pathlib.Path(archive).resolve(), pathlib.Path(output).resolve()
    if output.exists():
        raise ValueError('Output already exists; use a new directory.')
    if not 512 <= edge <= 4096 or not 60 <= quality <= 95:
        raise ValueError('Invalid display quality or dimensions.')
    output.mkdir(parents=True)
    (output / 'photos').mkdir()
    review = output / 'review'
    (review / 'thumbnails').mkdir(parents=True)
    records, source_records, duplicates, seen = [], [], [], {}
    original_bytes = 0
    original_pixels = 0
    original_archive_bytes = archive.stat().st_size
    srgb = ImageCms.createProfile('sRGB')
    with zipfile.ZipFile(archive) as source:
        members = [m for m in source.infolist() if not m.is_dir()]
        if len(members) > 2000 or sum(m.file_size for m in members) > 1024**3:
            raise ValueError('Archive exceeds photo-pool limits.')
        for index, member in enumerate(sorted(members, key=lambda m: natural_key(readable_name(m))), 1):
            name = readable_name(member)
            path = pathlib.PurePosixPath(member.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in member.filename or ':' in member.filename:
                raise ValueError('Unsafe archive member path.')
            if stat.S_ISLNK(member.external_attr >> 16):
                raise ValueError('Archive contains a symbolic link.')
            if path.suffix.lower() not in {'.jpg', '.jpeg', '.png', '.webp'}:
                raise ValueError('Unexpected file type; no archive instructions are executed.')
            if member.file_size > 30 * 1024**2:
                raise ValueError('A photo exceeds 30 MiB.')
            data = source.read(member)
            if len(data) != member.file_size or zlib.crc32(data) != member.CRC:
                raise ValueError('Archive CRC32 or length mismatch.')
            identifier = f'photo-{member.CRC:08x}-{len(data):x}'
            if identifier in seen:
                if data != source.read(seen[identifier]):
                    raise ValueError('CRC32 ID collision: stable IDs need manual resolution.')
                duplicates.append({'source': name, 'same_as': identifier})
                continue
            seen[identifier] = member
            with Image.open(io.BytesIO(data)) as image:
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                icc = image.info.get('icc_profile')
                original_size = image.size
                image = ImageOps.exif_transpose(image)
                if icc:
                    image = ImageCms.profileToProfile(
                        image, ImageCms.ImageCmsProfile(io.BytesIO(icc)), srgb,
                        outputMode='RGB',
                    )
                else:
                    image = image.convert('RGB')
                image.thumbnail((edge, edge), Image.Resampling.LANCZOS, reducing_gap=3)
                relative = f'photos/{identifier}.webp'
                target = output / relative
                image.save(target, 'WEBP', quality=quality, method=4)
                with Image.open(target) as check:
                    check.load()
                    if check.size != image.size or max(check.size) > edge:
                        raise ValueError('Display image dimensions mismatch.')
                encoded = target.read_bytes()
                thumb = image.copy()
                thumb.thumbnail((384, 384), Image.Resampling.LANCZOS, reducing_gap=3)
                thumb.save(review / 'thumbnails' / f'{identifier}.webp', 'WEBP', quality=74, method=4)
                records.append({
                    'id': identifier, 'file': relative, 'description': '',
                    'width': image.width, 'height': image.height,
                    'length': len(encoded), 'crc32': zlib.crc32(encoded),
                })
                source_records.append({
                    'id': identifier, 'source': name, 'original_bytes': len(data),
                    'original_dimensions': list(original_size),
                    'source_crc32': member.CRC,
                    'original_rgba_bytes': original_size[0] * original_size[1] * 4,
                    'display_rgba_bytes': image.width * image.height * 4,
                })
                original_bytes += len(data)
                original_pixels += original_size[0] * original_size[1]
            print(f'{index}/{len(members)} prepared {identifier}', flush=True)
    manifest = {'version': 1, 'photos': records}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (review / 'source-map.json').write_text(json.dumps(source_records, ensure_ascii=False, indent=2), encoding='utf-8')
    packaged = output / 'private-photo-pack.zip'
    with zipfile.ZipFile(packaged, 'w', zipfile.ZIP_DEFLATED) as bundle:
        bundle.write(output / 'manifest.json', 'manifest.json')
        for photo in records:
            bundle.write(output / photo['file'], photo['file'])
    with zipfile.ZipFile(packaged) as bundle:
        if bundle.testzip() is not None:
            raise ValueError('Photo pack CRC32 verification failed.')
    report = {
        'source_archive': str(archive), 'source_archive_bytes': original_archive_bytes,
        'input_photos': len(members), 'unique_photos': len(records), 'duplicates': duplicates,
        'original_photo_bytes': original_bytes,
        'display_photo_bytes': sum(p['length'] for p in records),
        'display_max_edge': edge, 'webp_quality': quality,
        'pack_bytes': packaged.stat().st_size,
        'thumbnail_bytes': sum(p.stat().st_size for p in (review / 'thumbnails').glob('*.webp')),
        'original_total_pixels': original_pixels,
        'display_total_pixels': sum(p['width'] * p['height'] for p in records),
        'verification': 'ZIP CRC32, lengths, full image decode, duplicate byte comparison',
        'originals_modified': False, 'uploaded': False,
        'runtime_integration': 'not installed in app; manifest is ready for existing IPA asset packer',
        'thumbnails': 'review derivatives only; excluded from app pack',
    }
    report['photo_size_reduction_percent'] = round((1 - report['display_photo_bytes'] / original_bytes) * 100, 2)
    (review / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--edge', type=int, default=2048)
    parser.add_argument('--quality', type=int, default=82)
    prepare(**vars(parser.parse_args()))
