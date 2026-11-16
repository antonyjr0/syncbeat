"""Tests for access-control interpretation in the metadata-only inventory."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "inventory", Path(__file__).with_name("zepp-manifest-inventory.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FIXTURE = '''  E: manifest (line=1)
    A: package="example.app" (Raw: "example.app")
      E: uses-sdk (line=2)
        A: http://schemas.android.com/apk/res/android:targetSdkVersion(0x01)=36
      E: queries (line=3)
          E: provider (line=4)
            A: http://schemas.android.com/apk/res/android:name(0x01)="NotAComponent" (Raw: "NotAComponent")
      E: application (line=5)
        A: http://schemas.android.com/apk/res/android:permission(0x01)="example.GUARD" (Raw: "example.GUARD")
          E: activity (line=6)
            A: http://schemas.android.com/apk/res/android:name(0x01)=".Internal" (Raw: ".Internal")
          E: activity (line=7)
            A: http://schemas.android.com/apk/res/android:name(0x01)=".Public" (Raw: ".Public")
            A: http://schemas.android.com/apk/res/android:exported(0x01)=true
            A: http://schemas.android.com/apk/res/android:permission(0x01)="example.SPECIAL" (Raw: "example.SPECIAL")
              E: intent-filter (line=8)
                  E: action (line=9)
                    A: http://schemas.android.com/apk/res/android:name(0x01)="android.intent.action.VIEW" (Raw: "android.intent.action.VIEW")
                  E: data (line=10)
                    A: http://schemas.android.com/apk/res/android:scheme(0x01)="content" (Raw: "content")
                  E: data (line=11)
                    A: http://schemas.android.com/apk/res/android:mimeType(0x01)="audio/mpeg" (Raw: "audio/mpeg")
          E: activity-alias (line=12)
            A: http://schemas.android.com/apk/res/android:name(0x01)=".Alias" (Raw: ".Alias")
            A: http://schemas.android.com/apk/res/android:targetActivity(0x01)=".Public" (Raw: ".Public")
          E: provider (line=13)
            A: http://schemas.android.com/apk/res/android:name(0x01)=".Files" (Raw: ".Files")
            A: http://schemas.android.com/apk/res/android:grantUriPermissions(0x01)=true
'''


class InventoryTests(unittest.TestCase):
    def test_default_export_and_queries_are_not_application_components(self):
        result = module.inventory(FIXTURE.encode())
        self.assertEqual(len(result["components"]), 4)
        self.assertFalse(result["components"][0]["exported"])
        self.assertEqual(result["components"][0]["permission"], "example.GUARD")
        self.assertFalse(result["components"][3]["exported"])
        self.assertEqual(result["components"][3]["attributes"]["grantUriPermissions"], "true")

    def test_explicit_export_filters_and_alias_permission_inheritance(self):
        result = module.inventory(FIXTURE.encode("utf-16"))
        component = result["components"][1]
        self.assertTrue(component["exported"])
        self.assertEqual(component["name"], "example.app.Public")
        self.assertEqual(component["intentFilters"][0]["data"], [{"scheme": "content"}, {"mimeType": "audio/mpeg"}])
        self.assertEqual(result["components"][2]["permission"], "example.SPECIAL")


if __name__ == "__main__":
    unittest.main()
