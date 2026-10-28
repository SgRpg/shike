"""Allowlisted source export and unsigned IPA packaging. No signing credentials.

ZIP CRC32 + lengths and structural checks are used throughout. Original files
are read only; all outputs must point to a new, dedicated directory/file.
"""
import argparse
import json
import pathlib
import plistlib
import zipfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'shike_ios'


def safe_output(path):
    path = pathlib.Path(path).resolve()
    if path.exists():
        raise ValueError(f'输出已存在，请使用新路径: {path}')
    return path


def source(output):
    output = safe_output(output)
    includes = ['lib', 'test', 'ios', 'assets', 'web', 'pubspec.yaml',
                'pubspec.lock', 'analysis_options.yaml', '.metadata']
    sources = []
    for name in includes:
        p = APP / name
        sources.extend(p.rglob('*') if p.is_dir() else [p])
    sources.extend([ROOT / 'README.md', ROOT / 'codemagic.yaml', ROOT / 'tools' / 'ios_delivery.py',
                    ROOT / 'tools' / 'test_ios_delivery.py'])
    sources.extend((ROOT / 'docs' / 'complete-ios').glob('*.md'))
    sources.extend((ROOT / 'docs' / 'complete-ios').glob('*.example.json'))
    excluded = {'Pods', '.symlinks', 'ephemeral', '.dart_tool', 'build',
                'private', 'private_assets', '.git', 'xcuserdata'}
    manifest = []
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for p in sorted(set(sources)):
            if not p.is_file() or excluded.intersection(part.lower() for part in p.relative_to(ROOT).parts):
                continue
            if p.suffix.lower() in {'.p12', '.p8', '.mobileprovision', '.key', '.pem', '.db', '.sqlite', '.zip', '.ipa'} or p.name.startswith('.env'):
                continue
            if p.name in {'Generated.xcconfig', 'flutter_export_environment.sh',
                          'GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m'}:
                continue
            relative = p.relative_to(ROOT).as_posix()
            data = p.read_bytes()
            manifest.append({'path': relative, 'length': len(data), 'crc32': zlib.crc32(data)})
            bundle.writestr(relative, data)
        bundle.writestr('SOURCE-MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2))
        bundle.writestr('.gitignore', 'envronment/\n**/build/\n**/.dart_tool/\n**/Pods/\n**/.symlinks/\n**/ephemeral/\n**/private/\n**/xcuserdata/\n*.ipa\n*.zip\n*.db\n*.mobileprovision\n*.p12\n.DS_Store\n')
    verify(output)
    print(f'已导出 {len(manifest)} 个白名单文件: {output}')


def package(app, output):
    app = pathlib.Path(app).resolve()
    output = safe_output(output)
    if not (app / 'Info.plist').is_file():
        raise ValueError('缺少 Runner.app/Info.plist')
    with (app / 'Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if not (app / info['CFBundleExecutable']).is_file():
        raise ValueError('缺少 iOS 可执行文件')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for p in sorted(app.rglob('*')):
            if p.is_file():
                bundle.write(p, f'Payload/{app.name}/{p.relative_to(app).as_posix()}')
    verify(output)
    print(f'未签名安装包: {output}')


def verify(path):
    with zipfile.ZipFile(path) as bundle:
        seen = set()
        for item in bundle.infolist():
            p = pathlib.PurePosixPath(item.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in item.filename or ':' in item.filename:
                raise ValueError('归档路径不安全')
            if item.filename in seen:
                raise ValueError('归档包含重复路径')
            seen.add(item.filename)
            data = bundle.read(item)
            if len(data) != item.file_size or zlib.crc32(data) != item.CRC:
                raise ValueError('归档完整性检查失败')


def assets(ipa, manifest, output):
    output = safe_output(output)
    spec_path = pathlib.Path(manifest).resolve()
    spec = json.loads(spec_path.read_text(encoding='utf-8-sig'))
    records, additions = [], {}
    for record in spec['photos']:
        identifier = record['id']
        if not identifier or not all(c.isascii() and (c.isalnum() or c in '-_') for c in identifier):
            raise ValueError('素材 ID 只能使用英文字母、数字、短横线和下划线')
        if any(r['id'] == identifier for r in records):
            raise ValueError('素材 ID 重复')
        path = (spec_path.parent / record['file']).resolve()
        if not path.is_relative_to(spec_path.parent) or not path.is_file():
            raise ValueError('照片必须在素材清单目录内')
        data = path.read_bytes()
        if len(data) > 30 * 1024 * 1024:
            raise ValueError('单张照片超过 30MB')
        name = f'photos/{identifier}{path.suffix.lower()}'
        additions[name] = data
        records.append({'id': identifier, 'file': name, 'length': len(data),
                        'crc32': zlib.crc32(data), 'description': record.get('description', '')})
    additions['manifest.json'] = json.dumps({'version': 1, 'photos': records}, ensure_ascii=False).encode()
    prefix = 'Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/private/'
    verify(ipa)
    with zipfile.ZipFile(ipa) as original, zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as result:
        if 'Payload/Runner.app/Info.plist' not in original.namelist():
            raise ValueError('不是拾刻的未签名安装包')
        if any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision') for n in original.namelist()):
            raise ValueError('请在签名前注入素材，不接受已签名安装包')
        for item in original.infolist():
            if not item.filename.startswith(prefix):
                result.writestr(item, original.read(item))
        for name, data in additions.items():
            result.writestr(prefix + name, data)
    verify(output)
    print(f'已加入 {len(records)} 张私人照片，接下来在 Windows 签名: {output}')


def preservation(baseline, report):
    baseline = pathlib.Path(baseline).resolve()
    names = json.loads((baseline / 'file-list.json').read_text(encoding='utf-8-sig'))
    changed = [n for n in names if not (APP / n).is_file() or (APP / n).read_bytes() != (baseline / n).read_bytes()]
    result = {'method': 'direct byte comparison', 'originalCount': len(names), 'changed': changed}
    safe_output(report).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest='command', required=True)
    p = commands.add_parser('source'); p.add_argument('--output', required=True)
    p = commands.add_parser('package'); p.add_argument('--app', required=True); p.add_argument('--output', required=True)
    p = commands.add_parser('assets'); p.add_argument('--ipa', required=True); p.add_argument('--manifest', required=True); p.add_argument('--output', required=True)
    p = commands.add_parser('preservation'); p.add_argument('--baseline', required=True); p.add_argument('--report', required=True)
    args = vars(cli.parse_args()); command = args.pop('command')
    {'source': source, 'package': package, 'assets': assets, 'preservation': preservation}[command](**args)
