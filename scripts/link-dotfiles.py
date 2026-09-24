#!/usr/bin/env python3
"""Safely link the configured dotfiles into a home directory."""

from __future__ import annotations

import argparse
import configparser
import os
import stat
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

BACKUP_PARENT = PurePosixPath(".local/state/dotfiles/backups")
OVERLAY_DIRECTORIES = (
    PurePosixPath(".config/listenbrainz-mpd"),
    PurePosixPath(".config/qutebrowser"),
    PurePosixPath(".config/systemd"),
    PurePosixPath(".local/share/qutebrowser/greasemonkey"),
    PurePosixPath(".local/share/qutebrowser/userscripts"),
)
FORBIDDEN_SOURCES = (
    PurePosixPath(".config/listenbrainz-mpd/token"),
)

@dataclass(frozen=True)
class Link:
    source_relative: PurePosixPath
    destination_relative: PurePosixPath
    source: Path
    destination: Path

@dataclass
class Plan:
    links: list[Link]
    conflicts: list[Link]
    already_correct: int
    directories: set[Path]

class PreflightError(Exception):
    pass

def lexists(path: Path) -> bool:
    return os.path.lexists(path)

def read_ini(path: Path) -> configparser.ConfigParser:
    config = configparser.ConfigParser(interpolation=None)
    try:
        with path.open(encoding="utf-8") as file:
            config.read_file(file)
    except (OSError, configparser.Error) as error:
        raise PreflightError(f"cannot read {path}: {error}") from error
    return config

def firefox_profile(target_home: Path) -> Path | None:
    for root in (
        target_home / ".config/mozilla/firefox",
        target_home / ".mozilla/firefox",
    ):
        profiles_ini = root / "profiles.ini"
        if not profiles_ini.is_file():
            continue
        profiles = read_ini(profiles_ini)

        candidates: list[str] = []
        installs_ini = root / "installs.ini"
        if installs_ini.is_file():
            installs = read_ini(installs_ini)
            candidates.extend(
                installs[section]["Default"]
                for section in installs.sections()
                if installs.has_option(section, "Default")
            )
        if not candidates:
            candidates.extend(
                profiles[section]["Default"]
                for section in profiles.sections()
                if section.startswith("Install") and profiles.has_option(section, "Default")
            )
        if not candidates:
            candidates.extend(
                profiles[section]["Path"]
                for section in profiles.sections()
                if section.startswith("Profile")
                and profiles.getboolean(section, "Default", fallback=False)
                and profiles.has_option(section, "Path")
            )
        if not candidates:
            candidates.extend(
                profiles[section]["Path"]
                for section in profiles.sections()
                if section.startswith("Profile") and profiles.has_option(section, "Path")
            )
        if not candidates:
            return None

        paths = {Path(value) for value in candidates}
        if len(paths) != 1:
            raise PreflightError(f"multiple Firefox defaults in {root}; choose one profile")
        relative_or_absolute = paths.pop()
        profile = root / relative_or_absolute
        if not profile.is_dir():
            raise PreflightError(f"Firefox profile does not exist: {profile}")
        resolved = profile.resolve(strict=True)
        if not is_within(resolved, target_home.resolve(strict=True)):
            raise PreflightError(f"Firefox profile is outside target home: {resolved}")
        return profile
    return None

def is_within(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory)
    except ValueError:
        return False
    return True

def discover_links(repo: Path, target_home: Path) -> list[Link]:
    for relative in FORBIDDEN_SOURCES:
        source = repo.joinpath(*relative.parts)
        if lexists(source):
            raise PreflightError(f"private source must not exist in repository: {source}")

    sources = [repo / ".gitconfig"]
    for directory in (repo / ".config", repo / ".local/bin"):
        sources.extend(
            sorted(
                p
                for p in directory.iterdir()
                if not p.name.startswith(".")
                and p.name != "__pycache__"
                and PurePosixPath(p.relative_to(repo).as_posix())
                not in OVERLAY_DIRECTORIES
            )
        )
    for relative in OVERLAY_DIRECTORIES:
        directory = repo.joinpath(*relative.parts)
        sources.extend(
            sorted(
                path
                for path in directory.rglob("*")
                if path.is_file()
                and "__pycache__" not in path.parts
                and not path.name.startswith(".")
            )
        )
    sources.append(repo / ".local/share/darkman")
    links = []
    for source in sources:
        if not source.exists():
            raise PreflightError(f"source does not exist: {source}")
        if source.is_symlink() or not (source.is_file() or source.is_dir()):
            raise PreflightError(f"source must be a regular file or directory: {source}")
        relative = PurePosixPath(source.relative_to(repo).as_posix())
        links.append(Link(relative, relative, source, target_home / relative))

    profile = firefox_profile(target_home)
    if profile is not None:
        for source_name, destination in (
            ("user.js", profile / "user.js"),
            ("userChrome.css", profile / "chrome/userChrome.css"),
        ):
            source_relative = PurePosixPath("firefox") / source_name
            destination_relative = PurePosixPath(destination.relative_to(target_home).as_posix())
            source = repo / source_relative
            if not source.is_file() or source.is_symlink():
                raise PreflightError(f"source must be a regular file: {source}")
            links.append(Link(source_relative, destination_relative, source, destination))
    return links

def equivalent(source: Path, destination: Path) -> bool:
    if not lexists(destination) or not destination.exists():
        return False
    try:
        return os.path.samefile(source, destination)
    except OSError:
        return False

def validate_target_home(target_home: Path, repo: Path) -> Path:
    if lexists(target_home):
        if target_home.is_symlink():
            raise PreflightError(f"target home must not be a symlink: {target_home}")
        if not target_home.is_dir():
            raise PreflightError(f"target home is not a directory: {target_home}")
    try:
        resolved = target_home.resolve(strict=False)
    except (OSError, RuntimeError) as error:
        raise PreflightError(
            f"cannot resolve target home {target_home}: {error}"
        ) from error
    if is_within(resolved, repo.resolve(strict=True)):
        raise PreflightError(
            f"target home resolves inside the dotfiles repository: {target_home}"
        )
    return resolved

def inspect_parents(
    target_home: Path,
    target_home_resolved: Path,
    destination: Path,
    repo_resolved: Path,
) -> set[Path]:
    missing: set[Path] = set()
    current = target_home
    parents = [target_home]
    for part in destination.parent.relative_to(target_home).parts:
        current /= part
        parents.append(current)

    for parent in parents:
        if not lexists(parent):
            missing.add(parent)
            continue
        if parent.is_symlink():
            raise PreflightError(f"destination parent must not be a symlink: {parent}")
        if not parent.is_dir():
            raise PreflightError(f"destination parent is not a directory: {parent}")
        try:
            resolved = parent.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise PreflightError(
                f"cannot resolve destination parent {parent}: {error}"
            ) from error
        if not is_within(resolved, target_home_resolved):
            raise PreflightError(
                f"destination parent resolves outside the target home: {parent} -> {resolved}"
            )
        if is_within(resolved, repo_resolved):
            raise PreflightError(
                f"destination parent resolves inside the dotfiles repository: {parent} -> {resolved}"
            )
    return missing

def make_plan(
    links: list[Link], target_home: Path, repo: Path, backup_conflicts: bool
) -> Plan:
    home_resolved = validate_target_home(target_home, repo)
    repo_resolved = repo.resolve(strict=True)
    planned: list[Link] = []
    conflicts: list[Link] = []
    directories: set[Path] = set()
    already = 0
    errors: list[str] = []

    for link in links:
        try:
            directories.update(
                inspect_parents(
                    target_home, home_resolved, link.destination, repo_resolved
                )
            )
        except PreflightError as error:
            errors.append(str(error))
            continue

        if equivalent(link.source, link.destination):
            already += 1
            continue
        if lexists(link.destination):
            mode = os.lstat(link.destination).st_mode
            can_back_up = stat.S_ISREG(mode) or stat.S_ISLNK(mode) or stat.S_ISDIR(mode)
            if backup_conflicts and can_back_up:
                conflicts.append(link)
                planned.append(link)
            elif backup_conflicts:
                errors.append(
                    f"conflicting destination is not a regular file, directory, or symlink: {link.destination}"
                )
            else:
                errors.append(f"destination already exists: {link.destination}")
            continue
        planned.append(link)

    if backup_conflicts and conflicts:
        backup_probe = target_home.joinpath(
            *BACKUP_PARENT.parts, "TIMESTAMP", "placeholder"
        )
        try:
            inspect_parents(target_home, home_resolved, backup_probe, repo_resolved)
        except PreflightError as error:
            errors.append(f"backup path is unsafe: {error}")

    if errors:
        raise PreflightError("\n".join(errors))
    return Plan(planned, conflicts, already, directories)

def backup_directory(target_home: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    candidate = target_home.joinpath(*BACKUP_PARENT.parts, stamp)
    counter = 1
    while lexists(candidate):
        candidate = target_home.joinpath(*BACKUP_PARENT.parts, f"{stamp}-{counter}")
        counter += 1
    return candidate

def print_plan(plan: Plan, apply: bool, target_home: Path) -> None:
    conflict_destinations = {link.destination for link in plan.conflicts}
    backup_preview = target_home.joinpath(*BACKUP_PARENT.parts, "TIMESTAMP")
    for link in plan.conflicts:
        backed_up = backup_preview.joinpath(*link.destination_relative.parts)
        if apply:
            print(
                f"BACK UP: {link.destination} (rollback directory reported after apply)"
            )
        else:
            print(f"WOULD BACK UP: {link.destination} -> {backed_up}")
    for link in plan.links:
        action = "LINK" if apply else "WOULD LINK"
        suffix = " (after backup)" if link.destination in conflict_destinations else ""
        print(f"{action}: {link.destination} -> {link.source}{suffix}")

def apply_plan(plan: Plan, target_home: Path) -> tuple[bool, Path | None, str | None]:
    created_directories: list[Path] = []
    created_links: list[Path] = []
    moved: list[tuple[Path, Path]] = []
    backup_root = backup_directory(target_home) if plan.conflicts else None

    try:
        directories = set(plan.directories)
        if backup_root is not None:
            current = target_home
            for part in backup_root.relative_to(target_home).parts:
                current /= part
                directories.add(current)
            for link in plan.conflicts:
                current = backup_root
                for part in link.destination_relative.parent.parts:
                    current /= part
                    directories.add(current)

        for directory in sorted(directories, key=lambda item: len(item.parts)):
            if lexists(directory):
                if directory == backup_root:
                    raise OSError(
                        f"fresh backup directory became occupied: {directory}"
                    )
                if directory.is_symlink() or not directory.is_dir():
                    raise OSError(f"planned directory became unsafe: {directory}")
                continue
            directory.mkdir(mode=0o700)
            os.chmod(directory, 0o700)
            created_directories.append(directory)

        if backup_root is not None:
            os.chmod(backup_root, 0o700)
            for link in plan.conflicts:
                backed_up = backup_root.joinpath(*link.destination_relative.parts)
                link.destination.rename(backed_up)
                moved.append((link.destination, backed_up))

        for link in plan.links:
            if lexists(link.destination):
                raise OSError(
                    f"destination appeared after preflight: {link.destination}"
                )
            link.destination.symlink_to(link.source)
            created_links.append(link.destination)
    except OSError as error:
        rollback_errors: list[str] = []
        for destination in reversed(created_links):
            try:
                destination.unlink()
            except OSError as rollback_error:
                rollback_errors.append(
                    f"could not remove {destination}: {rollback_error}"
                )
        for destination, backed_up in reversed(moved):
            try:
                if lexists(destination):
                    raise OSError("destination is occupied")
                backed_up.rename(destination)
            except OSError as rollback_error:
                rollback_errors.append(
                    f"could not restore {destination} from {backed_up}: {rollback_error}"
                )
        for directory in sorted(
            created_directories, key=lambda item: len(item.parts), reverse=True
        ):
            try:
                directory.rmdir()
            except OSError:
                pass
        message = str(error)
        if rollback_errors:
            message += "; rollback incomplete: " + "; ".join(rollback_errors)
        return False, backup_root, message

    return True, backup_root, None

def run(
    repo: Path,
    target_home: Path,
    apply: bool,
    backup_conflicts: bool,
) -> int:
    try:
        links = discover_links(repo, target_home)
        plan = make_plan(links, target_home, repo, backup_conflicts)
    except PreflightError as error:
        for line in str(error).splitlines():
            print(f"CONFLICT: {line}", file=sys.stderr)
        print("Preflight failed; no changes made.", file=sys.stderr)
        return 1

    print_plan(plan, apply, target_home)
    if not apply:
        print(
            f"Dry run: {len(plan.links)} link(s) planned, "
            f"{len(plan.conflicts)} conflict(s) would be backed up, "
            f"{plan.already_correct} already correct."
        )
        return 0

    succeeded, backup_root, error = apply_plan(plan, target_home)
    if not succeeded:
        print(f"Apply failed: {error}", file=sys.stderr)
        return 2
    if backup_root is not None:
        print(f"Rollback files preserved at: {backup_root}")
    print(
        f"Applied: {len(plan.links)} link(s), {len(plan.conflicts)} conflict(s) backed up, "
        f"{plan.already_correct} already correct."
    )
    return 0

def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="create links after a successful full preflight (default: dry run)",
    )
    parser.add_argument(
        "--backup-conflicts",
        action="store_true",
        help="preserve existing files and directories before linking",
    )
    parser.add_argument(
        "--target-home",
        type=Path,
        default=Path.home(),
        help="home directory to populate (default: the current user's home)",
    )
    return parser.parse_args(argv)

def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = Path(__file__).resolve().parent.parent
    target_home = Path(os.path.abspath(args.target_home.expanduser()))
    return run(repo, target_home, args.apply, args.backup_conflicts)

if __name__ == "__main__":
    raise SystemExit(main())
