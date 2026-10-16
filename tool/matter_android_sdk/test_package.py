# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
import tempfile
import unittest
import io
import struct
from pathlib import Path
import zipfile

from package import archive, merge_jars, validate_elf


class PackagingTests(unittest.TestCase):
    def test_archive_has_stable_order_and_metadata(self):
        self.assertEqual(archive({"b": b"2", "a": b"1"}), archive({"a": b"1", "b": b"2"}))

    def test_merges_controller_classes_and_rejects_conflicts(self):
        with tempfile.TemporaryDirectory() as folder:
            first, second = Path(folder) / "controller.jar", Path(folder) / "platform.jar"
            first.write_bytes(archive({"chip/devicecontroller/ChipDeviceController.class": b"controller"}))
            second.write_bytes(archive({"chip/platform/AndroidChipPlatform.class": b"platform"}))
            with zipfile.ZipFile(io.BytesIO(merge_jars([first, second]))) as result:
                self.assertEqual(len(result.namelist()), 2)
            second.write_bytes(archive({"chip/devicecontroller/ChipDeviceController.class": b"different"}))
            with self.assertRaisesRegex(ValueError, "Conflicting"):
                merge_jars([first, second])

    def test_missing_public_classes_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            jar = Path(folder) / "empty.jar"
            jar.write_bytes(archive({"irrelevant.class": b""}))
            with self.assertRaisesRegex(ValueError, "Missing public"):
                merge_jars([jar])

    def test_rejects_unsafe_jar_entries(self):
        with tempfile.TemporaryDirectory() as folder:
            jar = Path(folder) / "bad.jar"
            jar.write_bytes(archive({"../outside.class": b""}))
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                merge_jars([jar])

    def test_requires_arm64_and_16k_load_alignment(self):
        data = bytearray(120)
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, 183)
        struct.pack_into("<Q", data, 32, 64)
        struct.pack_into("<HH", data, 54, 56, 1)
        struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, 0, 0, 0, 0, 16384)
        validate_elf(data)
        struct.pack_into("<Q", data, 112, 4096)
        with self.assertRaisesRegex(ValueError, "16-KiB"):
            validate_elf(data)


if __name__ == "__main__":
    unittest.main()
