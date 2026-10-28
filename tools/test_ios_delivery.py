import json
import pathlib
import plistlib
import tempfile
import unittest
import zipfile
import ios_delivery as delivery


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='shike-delivery-')
        self.root = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def app(self):
        app = self.root / 'Runner.app'; app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Runner'}))
        (app / 'Runner').write_bytes(b'fake test executable')
        return app

    def test_ipa_packaging_and_asset_injection_do_not_mutate_input(self):
        app = self.app(); original = self.root / 'unsigned.ipa'
        delivery.package(app, original); before = original.read_bytes()
        folder = self.root / 'private'; folder.mkdir()
        (folder / 'picture.jpg').write_bytes(b'test image')
        (folder / 'manifest.json').write_text(json.dumps({'version': 1, 'photos': [
            {'id': 'stable-001', 'file': 'picture.jpg', 'description': 'test'}]}))
        output = self.root / 'with-assets.ipa'
        delivery.assets(original, folder / 'manifest.json', output)
        self.assertEqual(before, original.read_bytes())
        with zipfile.ZipFile(output) as archive:
            prefix = 'Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/private/'
            manifest = json.loads(archive.read(prefix + 'manifest.json'))
            self.assertEqual(manifest['photos'][0]['id'], 'stable-001')
            self.assertEqual(manifest['photos'][0]['length'], len(b'test image'))

    def test_archive_traversal_is_rejected(self):
        bad = self.root / 'bad.zip'
        with zipfile.ZipFile(bad, 'w') as archive:
            archive.writestr('../outside', b'bad')
        with self.assertRaises(ValueError): delivery.verify(bad)

    def test_source_export_excludes_environment_private_photos_and_credentials(self):
        previous_root, previous_app = delivery.ROOT, delivery.APP
        try:
            delivery.ROOT = self.root; delivery.APP = self.root / 'shike_ios'
            for name in ['lib/main.dart', 'lib/signing.key', 'assets/private/picture.jpg',
                         'assets/phrases.json', 'ios/Runner/Info.plist', 'envronment/secret.txt']:
                path = delivery.APP / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('test')
            output = self.root / 'source.zip'; delivery.source(output)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
            self.assertIn('shike_ios/lib/main.dart', names)
            self.assertIn('shike_ios/assets/phrases.json', names)
            self.assertFalse(any('/private/' in n or '/envronment/' in n or n.endswith('.key') for n in names))
        finally:
            delivery.ROOT, delivery.APP = previous_root, previous_app


if __name__ == '__main__':
    unittest.main()
