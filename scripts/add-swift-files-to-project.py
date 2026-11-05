"""Register Swift files in RecompTV.xcodeproj the way LibraryView.swift is registered."""
import pathlib
import sys
import uuid

project = pathlib.Path(sys.argv[1])
text = project.read_text()
ANCHOR = '"370340BBE638A857F7D98094" = { "isa" = "PBXBuildFile"; "fileRef" = "042064B99A910D4E9735395E"; };\n'
CHILD = '\t\t\t\t"042064B99A910D4E9735395E",\n'
PHASE = '\t\t\t\t"370340BBE638A857F7D98094",\n'
assert text.count(ANCHOR) == 1 and text.count(CHILD) == 1 and text.count(PHASE) == 2, "project layout changed"


def new_id():
    while True:
        candidate = uuid.uuid4().hex[:24].upper()
        if candidate not in text:
            return candidate


for path in sys.argv[2:]:
    if f'"path" = "{path}"' in text:
        print("already registered:", path)
        continue
    ref, build = new_id(), new_id()
    text = text.replace(ANCHOR, ANCHOR
        + f'\t\t"{ref}" = {{ "isa" = "PBXFileReference"; "lastKnownFileType" = "sourcecode.swift"; "path" = "{path}"; "sourceTree" = "SOURCE_ROOT"; }};\n'
        + f'\t\t"{build}" = {{ "isa" = "PBXBuildFile"; "fileRef" = "{ref}"; }};\n')
    text = text.replace(CHILD, CHILD + f'\t\t\t\t"{ref}",\n')
    text = text.replace(PHASE, PHASE + f'\t\t\t\t"{build}",\n')
    print("registered:", path, ref, build)
project.write_text(text)
