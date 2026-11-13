import json
import pathlib
import sys

folder = pathlib.Path(sys.argv[1])
for test in json.loads((folder / "manifest.json").read_text()):
    for attachment in test["attachments"]:
        exported = folder / attachment["exportedFileName"]
        label = attachment["suggestedHumanReadableName"].split("_")[0]
        if exported.exists():
            exported.rename(folder / f"{label}{exported.suffix}")
