import json
import pathlib
import sys

folder = pathlib.Path(sys.argv[1])
for test in json.loads((folder / "manifest.json").read_text()):
    for attachment in test["attachments"]:
        exported = folder / attachment["exportedFileName"]
        label = attachment["suggestedHumanReadableName"].split("_")[0]
        # A failed test attaches files named after a query, quotes and all, and the artifact upload
        # refuses a name with any of these characters. That lost the screenshots of a failed run.
        label = "".join("-" if character in '"<>|*?:\\/\r\n' else character for character in label)
        if exported.exists():
            exported.rename(folder / f"{label}{exported.suffix}")
