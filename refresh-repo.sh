#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

OLD_VER=0.12.1
NEW_VER=0.13.0

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=stash-updater # -$(date +%s)
# COMMIT_MSG="Use restic ${NEW_VER}"
COMMIT_MSG="Use restic 0.13.0"

REPO_ROOT=/tmp/stash-updater

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.in
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.dbg
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.test || true
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.in
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.dbg
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.test || true
    sed -i "s|RESTIC_VER\([[:space:]]*\):= ${OLD_VER}|RESTIC_VER\1:= ${NEW_VER}|g" Makefile
    sed -i "s|strng{\"stash-enterprise\"}|string{\"stash-enterprise\",\ \"kubedb-ext-stash\"}|g" pkg/root.go
    if [ -f go.mod ]; then
        go mod edit \
            -require=kmodules.xyz/client-go@2a6d5a5784f241725e193988fd238255d737569f \
            -require=kmodules.xyz/monitoring-agent-api@0290ed5b75e16eb2d3a6066851ae5570d101b6f8 \
            -require=kmodules.xyz/webhook-runtime@0ddfc9e4c2214ebcc4acd9e33d2f8e9880de1428 \
            -require=kmodules.xyz/resource-metadata@v0.10.12 \
            -require=kmodules.xyz/custom-resources@7beb809b1f5eb5dd1bbe61494513f3ccc5fcd9a5 \
            -require=kmodules.xyz/objectstore-api@f1d593d0a778b3f502dfff9cdcb759ac5e55e6a4 \
            -require=kmodules.xyz/offshoot-api@3b0fd2ea77d65eaad436940b8d21abbaf2421922 \
            -require=go.bytebuilders.dev/license-verifier@v0.9.7 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.9.7 \
            -require=go.bytebuilders.dev/audit@v0.0.19 \
            -require=gomodules.xyz/x@v0.0.13 \
            -require=gomodules.xyz/logs@v0.0.6 \
            -replace=github.com/satori/go.uuid=github.com/gomodules/uuid@v4.0.0+incompatible \
            -replace=github.com/dgrijalva/jwt-go=github.com/gomodules/jwt@v3.2.2+incompatible \
            -replace=github.com/golang-jwt/jwt=github.com/golang-jwt/jwt@v3.2.2+incompatible \
            -replace=github.com/form3tech-oss/jwt-go=github.com/form3tech-oss/jwt-go@v3.2.5+incompatible \
            -replace=helm.sh/helm/v3=github.com/kubepack/helm/v3@v3.6.1-0.20210518225915-c3e0ce48dd1b \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.21.2-0.20220112070009-e3f6e88991d9
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # always run make fmt incase make gen fmt fails
        make fmt || true
    )
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
