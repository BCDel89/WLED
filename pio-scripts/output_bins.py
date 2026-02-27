Import('env')
import os
import re
import shutil
import gzip
import subprocess
from datetime import datetime

OUTPUT_DIR = "build_output{}".format(os.path.sep)
#OUTPUT_DIR = os.path.join("build_output")

def _get_cpp_define_value(env, define):
    define_list = [item[-1] for item in env["CPPDEFINES"] if item[0] == define]

    if define_list:
        return define_list[0]

    return None

def _create_dirs(dirs=["map", "release", "firmware"]):
    for d in dirs:
        os.makedirs(os.path.join(OUTPUT_DIR, d), exist_ok=True)

def create_release(source):
    release_name_def = _get_cpp_define_value(env, "WLED_RELEASE_NAME")
    if release_name_def:
        release_name = release_name_def.replace("\\\"", "")
        version = _get_cpp_define_value(env, "WLED_VERSION")
        release_file = os.path.join(OUTPUT_DIR, "release", f"WLED_{version}_{release_name}.bin")
        release_gz_file = release_file + ".gz"
        print(f"Copying {source} to {release_file}")
        shutil.copy(source, release_file)
        bin_gzip(release_file, release_gz_file)
    else:
        variant = env["PIOENV"]
        bin_file = "{}firmware{}{}.bin".format(OUTPUT_DIR, os.path.sep, variant)
        print(f"Copying {source} to {bin_file}")
        shutil.copy(source, bin_file)

def bin_rename_copy(source, target, env):
    _create_dirs()
    variant = env["PIOENV"]
    builddir = os.path.join(env["PROJECT_BUILD_DIR"],  variant)
    source_map = os.path.join(builddir, env["PROGNAME"] + ".map")

    # create string with location and file names based on variant
    map_file = "{}map{}{}.map".format(OUTPUT_DIR, os.path.sep, variant)

    create_release(str(target[0]))

    # copy firmware.map to map/<variant>.map
    if os.path.isfile("firmware.map"):
        print("Found linker mapfile firmware.map")
        shutil.copy("firmware.map", map_file)
    if os.path.isfile(source_map):
        print(f"Found linker mapfile {source_map}")
        shutil.copy(source_map, map_file)

def bin_gzip(source, target):
    # only create gzip for esp8266
    if not env["PIOPLATFORM"] == "espressif8266":
        return
    
    print(f"Creating gzip file {target} from {source}")
    with open(source,"rb") as fp:
        with gzip.open(target, "wb", compresslevel = 9) as f:
            shutil.copyfileobj(fp, f)

def _get_git_branch():
    try:
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        return branch if branch else "unknown"
    except Exception:
        return "unknown"

def _normalize_branch(branch):
    # Replace slashes, backslashes, underscores, spaces with hyphens
    normalized = re.sub(r'[/\\_ ]+', '-', branch)
    # Collapse multiple hyphens
    normalized = re.sub(r'-+', '-', normalized)
    return normalized.strip('-')

def copy_to_dated_release_dir(source, target, env):
    date_str = datetime.now().strftime("%m-%d-%y")
    branch = _get_git_branch()
    normalized_branch = _normalize_branch(branch)
    dir_name = f"{date_str}-{normalized_branch}"
    dest_dir = os.path.join(OUTPUT_DIR, dir_name)
    os.makedirs(dest_dir, exist_ok=True)

    variant = env["PIOENV"]
    build_dir = os.path.join(env["PROJECT_BUILD_DIR"], variant)

    # Files to copy from the PlatformIO build directory
    build_files = ["firmware.bin", "bootloader.bin", "partitions.bin", "littlefs.bin"]
    for fname in build_files:
        src = os.path.join(build_dir, fname)
        if os.path.isfile(src):
            dst = os.path.join(dest_dir, fname)
            print(f"[release-dir] Copying {src} -> {dst}")
            shutil.copy(src, dst)
        else:
            print(f"[release-dir] Skipping {fname} (not found)")

    # Also copy the named release binary from build_output/release/
    release_dir = os.path.join(OUTPUT_DIR, "release")
    if os.path.isdir(release_dir):
        for f in os.listdir(release_dir):
            if f.endswith(".bin") or f.endswith(".bin.gz"):
                src = os.path.join(release_dir, f)
                dst = os.path.join(dest_dir, f)
                print(f"[release-dir] Copying {src} -> {dst}")
                shutil.copy(src, dst)

    print(f"[release-dir] Release files saved to: {dest_dir}")

env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", bin_rename_copy)
env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", copy_to_dated_release_dir)
