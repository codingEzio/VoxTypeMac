set shell := ["bash", "-euo", "pipefail", "-c"]

verify:
    ./verify-source.sh

diagram:
    "$HOME/X/Setup/Utilities/Bin/plantuml_project" Architectural-Overview.puml

build:
    ./build-app.sh

stage:
    ./script/build_and_run.sh --stage

package:
    ./script/package_release.sh

icon:
    ./script/build_icon.sh

run:
    ./script/build_and_run.sh

rerun:
    ./script/build_and_run.sh

install:
    ./install.sh
