"""Pinned upstream game sources for the tvOS build.

Each game has a version file, upstream/<game>-baseline.json, with the upstream
"release" Nativecade builds and its "sources". The one source without a
"gitlink" is the game's own repository; a source with a "gitlink" is a library
taken from that release's submodule, so its version always follows the game's.
"prepare" lists the scripts that apply our tvOS patches to generated copies.
A source with a "branch" follows that branch of its own repository instead of the
game's release (Racer's setup clones its toolkits that way), so updating the game
leaves it alone; "checkout" names its folder under build/upstream.
Only what the tvOS build compiles is pinned and fetched; other platforms'
submodules and tooling are never downloaded.

  python3 scripts/upstream.py fetch [NAME ...]           check out the pinned sources
  python3 scripts/upstream.py update GAME RELEASE        pin a release and check our patches
  python3 scripts/upstream.py releases [--open-issues]   compare pins with the latest releases
"""

import argparse
import copy
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
GUIDE = "docs/UPDATING_UPSTREAM.md"


class Pin(NamedTuple):
    name: str
    repository: str
    revision: str
    path: Path


def load_games(root=ROOT):
    """Tracked games by key. Research baselines without a "release" are not games."""
    games = {}
    for path in sorted((root / "upstream").glob("*-baseline.json")):
        data = json.loads(path.read_text())
        if "release" in data:
            games[path.name.removesuffix("-baseline.json")] = data
    return games


def game_source(game):
    """The game's own repository: its one source that is not a submodule."""
    own = [(name, source) for name, source in game["sources"].items()
           if "gitlink" not in source and "branch" not in source]
    if len(own) != 1:
        raise SystemExit("A game version file needs exactly one source without a gitlink")
    return own[0]


def checkouts(games, root=ROOT):
    """Every pinned source, once. Games that share a library must pin one revision of it."""
    pins = {}
    for game in games.values():
        for name, source in game["sources"].items():
            path = root / "build/upstream" / source.get("checkout", source["repository"].split("/")[1])
            pin = pins.setdefault(path, Pin(name, source["repository"], source["revision"], path))
            if pin.revision != source["revision"]:
                raise SystemExit(f"{path.name} is pinned to two different revisions")
    return list(pins.values())


def update_pins(game, release, revision, gitlinks, today):
    """The game's version data at RELEASE. Libraries follow that release's submodules."""
    updated = copy.deepcopy(game)
    updated["release"], updated["recorded_on"] = release, today
    for source in updated["sources"].values():
        if "branch" in source:
            continue
        if "gitlink" not in source:
            source["revision"] = revision
        elif source["gitlink"] in gitlinks:
            source["revision"] = gitlinks[source["gitlink"]]
        else:
            raise SystemExit(f"{release} has no {source['gitlink']} submodule; the integration needs review")
    return updated


def refreshed_rom_reference(reference, data, revision):
    """The supported-ROM reference for the hash list DATA taken from REVISION."""
    prefix, rest = reference["source"].split("/blob/")
    updated = dict(reference)
    updated["source"] = f"{prefix}/blob/{revision}/{rest.split('/', 1)[1]}"
    updated["file_sha256"] = hashlib.sha256(data).hexdigest()
    updated["upstream_entry_count"] = len(json.loads(data))
    return updated


def release_issue(key, game, latest, summary=""):
    """Title and body for a new-release issue, or None when the pin is current."""
    if latest == game["release"]:
        return None
    source = game_source(game)[1]
    repository, revision = source["repository"], source["revision"]
    title = f"Update {repository.split('/')[1]} to {latest}"
    body = (f"[{repository} {latest}](https://github.com/{repository}/releases/tag/{latest}) is out; "
            f"Nativecade builds {game['release']}.\n\n"
            f"Changes since our pin: https://github.com/{repository}/compare/{revision}...{latest}\n"
            f"{summary}\nTo start the update:\n\n"
            f"```sh\npython3 scripts/upstream.py update {key} {latest}\n```\n\n"
            f"Then follow [{GUIDE}](../blob/main/{GUIDE}).\n")
    return title, body


def run(*args, cwd=ROOT, check=True):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode:
        raise SystemExit(f"{' '.join(map(str, args))} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def fetch(pin):
    """Check out PIN's exact commit without submodules; fetch only when it is missing."""
    path = pin.path
    if not (path / ".git").exists():
        path.mkdir(parents=True, exist_ok=True)
        run("git", "init", "-q", cwd=path)
    if run("git", "status", "--porcelain", cwd=path):
        raise SystemExit(f"{path} has local changes; upstream checkouts must stay clean")
    if run("git", "rev-parse", "-q", "--verify", "HEAD", cwd=path, check=False) != pin.revision:
        missing = subprocess.run(["git", "cat-file", "-e", f"{pin.revision}^{{commit}}"], cwd=path,
                                 capture_output=True).returncode
        if missing:
            run("git", "fetch", "-q", "--depth", "1", f"https://github.com/{pin.repository}.git", pin.revision, cwd=path)
        run("git", "checkout", "-q", "--detach", pin.revision, cwd=path)
    print(f"{pin.name}: {pin.repository} {pin.revision[:12]}")


def release_revision(repository, release):
    """The commit a release tag points to, following annotated tags."""
    refs = {}
    for line in run("git", "ls-remote", f"https://github.com/{repository}.git",
                    f"refs/tags/{release}", f"refs/tags/{release}^{{}}").splitlines():
        sha, ref = line.split("\t")
        refs[ref] = sha
    revision = refs.get(f"refs/tags/{release}^{{}}") or refs.get(f"refs/tags/{release}")
    if not revision:
        raise SystemExit(f"{repository} has no release tag {release}")
    return revision


def update(key, release):
    games = load_games()
    if key not in games:
        raise SystemExit(f"Unknown game {key!r}; tracked: {', '.join(games)}")
    game = games[key]
    name, source = game_source(game)
    revision = release_revision(source["repository"], release)
    path = ROOT / "build/upstream" / source["repository"].split("/")[1]
    fetch(Pin(name, source["repository"], revision, path))
    gitlinks = {}
    for line in run("git", "ls-tree", "-r", revision, cwd=path).splitlines():
        mode, kind, sha, tree_path = line.split(None, 3)
        if kind == "commit":
            gitlinks[tree_path] = sha
    updated = update_pins(game, release, revision, gitlinks, datetime.date.today().isoformat())
    if "rom_reference" in updated:
        reference = updated["rom_reference"]
        upstream_path = reference["source"].split("/blob/")[1].split("/", 1)[1]
        data = subprocess.run(["git", "show", f"{revision}:{upstream_path}"], cwd=path,
                              capture_output=True, check=True).stdout
        updated["rom_reference"] = refreshed_rom_reference(reference, data, revision)
        for copy_path in (reference["local_path"], reference["app_copy"]):
            (ROOT / copy_path).write_bytes(data)
    (ROOT / f"upstream/{key}-baseline.json").write_text(json.dumps(updated, indent=2) + "\n")
    for old, new in zip(game["sources"].items(), updated["sources"].items()):
        if old[1]["revision"] != new[1]["revision"]:
            print(f"{new[0]}: {old[1]['revision'][:12]} -> {new[1]['revision'][:12]} "
                  f"https://github.com/{new[1]['repository']}/compare/{old[1]['revision']}...{new[1]['revision']}")
    games[key] = updated
    for pin in checkouts(games):
        fetch(pin)
    # Shared libraries can break another game's patches, so every game's patches are checked.
    failures = []
    for other in games.values():
        for step in other.get("prepare", []):
            result = subprocess.run(["python3", *step], cwd=ROOT, capture_output=True, text=True)
            print(f"{'ok  ' if result.returncode == 0 else 'FAIL'} {' '.join(step)}")
            if result.returncode:
                failures.append(step)
                print("     " + "\n     ".join((result.stdout + result.stderr).strip().splitlines()[-8:]))
    if game["sources"].get("libultraship", {}).get("revision") != updated["sources"].get("libultraship", {}).get("revision"):
        print("libultraship changed: re-record its dependency pins with "
              "`bash scripts/check-shipwright-metal.sh arm64 build/upstream/libultraship --record-dependencies`.")
    print(f"Pinned {key} {release}. {len(failures)} patch step(s) need attention; next steps are in {GUIDE}.")
    return 1 if failures else 0


def gh(*args):
    return run("gh", *args)


def releases(open_issues):
    for key, game in load_games().items():
        source = game_source(game)[1]
        latest = gh("api", f"repos/{source['repository']}/releases/latest", "--jq", ".tag_name")
        if latest == game["release"]:
            print(f"{key}: {game['release']} is the latest release")
            continue
        compare = json.loads(gh("api", f"repos/{source['repository']}/compare/{source['revision']}...{latest}",
                                "--jq", "{commits: .total_commits, files: [.files[].filename]}"))
        libraries = [s["gitlink"] for s in game["sources"].values() if "gitlink" in s and s["gitlink"] in compare["files"]]
        summary = (f"{compare['commits']} commits, {len(compare['files'])} changed files"
                   f"{' (GitHub lists at most 300)' if len(compare['files']) >= 300 else ''}. "
                   f"Shared libraries changed: {', '.join(libraries) or 'none'}.\n")
        title, body = release_issue(key, game, latest, summary)
        print(f"{key}: {latest} is available; Nativecade builds {game['release']}")
        if not open_issues:
            continue
        titles = gh("issue", "list", "--state", "all", "--search", f'in:title "{title}"', "--json", "title", "--jq", ".[].title")
        if title not in titles.splitlines():
            print(gh("issue", "create", "--title", title, "--body", body))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    fetch_parser = commands.add_parser("fetch")
    fetch_parser.add_argument("names", nargs="*")
    update_parser = commands.add_parser("update")
    update_parser.add_argument("game")
    update_parser.add_argument("release")
    releases_parser = commands.add_parser("releases")
    releases_parser.add_argument("--open-issues", action="store_true")
    args = parser.parse_args()
    if args.command == "fetch":
        pins = [pin for pin in checkouts(load_games()) if not args.names or pin.name in args.names]
        if args.names and len(pins) != len(set(args.names)):
            raise SystemExit(f"Unknown source; pinned: {', '.join(p.name for p in checkouts(load_games()))}")
        for pin in pins:
            fetch(pin)
        return 0
    if args.command == "update":
        return update(args.game, args.release)
    releases(args.open_issues)
    return 0


if __name__ == "__main__":
    sys.exit(main())
