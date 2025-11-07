#!/bin/sh

set -e

SELF_PATH="$(readlink --canonicalize-existing -- "$0")"
SELF_DIR="${SELF_PATH%/*}"
SELF_BASE="${SELF_PATH##*/}"

usage ()
{
	printf 'Usage: %s config\n' "${SELF_BASE}"
	exit 1
}

BOOTSTRAP_CONFIG=''
BOOTSTRAP_CONFIG_OS=''
BOOTSTRAP_CONFIG_OS_COMPILER=''
BOOTSTRAP_CONFIG_CUDA=''
BOOTSTRAP_CONFIG_CUDA_COMPILER=''
BOOTSTRAP_MIRROR="$(realpath "$(pwd)/../spack-mirror")"
#BOOTSTRAP_MIRROR=''

bootstrap_apply_pr ()
{
	local pr
	local repo

	repo="$1"
	pr="$2"

	test -n "${repo}" || return 1
	test -n "${pr}" || return 1

	rm --force "${pr}.diff"
	curl --fail --location --remote-name "https://github.com/spack/${repo}/pull/${pr}.diff"
	git apply --verbose "${pr}.diff"
}

bootstrap_get_os ()
{
	./bin/spack arch --operating-system
}

bootstrap_install ()
{
	local compiler
	local package

	package="$1"
	compiler="$2"

	test -n "${package}" || return 1

	if test -n "${compiler}"
	then
		compiler="%${compiler}"
	fi

	if test -n "${BOOTSTRAP_MIRROR}"
	then
		echo "Mirroring ${package}"
		# FIXME Mirroring for missing compilers currently does not work (https://github.com/spack/spack/issues/43092)
		./bin/spack mirror create --directory "${BOOTSTRAP_MIRROR}" --dependencies "${package}" ${compiler}
	fi

	echo "Installing ${package}"
	./bin/spack install "${package}" ${compiler}
}

bootstrap_install_compiler ()
{
	local compiler
	local location
	local package

	package="$1"
	compiler="$2"

	test -n "${package}" || return 1
	test -n "${compiler}" || return 1

	bootstrap_install "${package}" "${compiler}"

	location="$(./bin/spack location --install-dir "${package}" "%${compiler}")"
	./bin/spack compiler find "${location}"
}

bootstrap_create_env ()
{
	sed \
		--expression="s#@BOOTSTRAP_CONFIG@#${BOOTSTRAP_CONFIG}#g" \
		--expression="s#@SPACK_ROOT@#$(pwd)#g" \
		../env.sh.in > ../env.sh
}

BOOTSTRAP_CONFIG="$1"

test -n "${BOOTSTRAP_CONFIG}" || usage

case "${BOOTSTRAP_CONFIG}" in
	ants)
		BOOTSTRAP_CONFIG_OS='rocky9'
		BOOTSTRAP_CONFIG_OS_COMPILER='gcc@11'
		BOOTSTRAP_CONFIG_CUDA='12.3'
		BOOTSTRAP_CONFIG_CUDA_COMPILER='gcc@12'
		;;
	sofja)
		BOOTSTRAP_CONFIG_OS='rocky8'
		BOOTSTRAP_CONFIG_OS_COMPILER='gcc@8'
		BOOTSTRAP_CONFIG_CUDA='12.4'
		BOOTSTRAP_CONFIG_CUDA_COMPILER='gcc@13'
		;;
	*)
		printf 'Config %s is not supported.\n' "${BOOTSTRAP_CONFIG}"
		exit 1
		;;
esac

if test -f /etc/profile.d/modules.sh
then
	. /etc/profile.d/modules.sh
fi

if command -v module >/dev/null 2>&1
then
	module purge
fi

cd spack

export SPACK_DISABLE_LOCAL_CONFIG=1
# FIXME set SPACK_USER_CACHE_PATH?

pushd ../spack-packages

git checkout --force

#bootstrap_apply_pr spack-packages xyz
bootstrap_apply_pr spack-packages 2327

popd

git checkout --force

# FIXME Find a better way to do this
git apply --verbose ../patches/env.patch

#bootstrap_apply_pr spack xyz
bootstrap_apply_pr spack 43158
bootstrap_apply_pr spack 43519

rm --force --recursive "${HOME}/.spack"

rm --force etc/spack/mirrors.yaml

cp ../config/concretizer.yaml etc/spack
cp ../config/config.yaml etc/spack
cp ../config/modules.yaml etc/spack

sed \
	--expression="s#@BOOTSTRAP_CONFIG_CUDA@#${BOOTSTRAP_CONFIG_CUDA}#g" \
	../config/packages.yaml.in > etc/spack/packages.yaml

./bin/spack repo set --destination "$(realpath --canonicalize-existing ../spack-packages)" builtin

if test -n "${BOOTSTRAP_MIRROR}"
then
	mkdir --parents "${BOOTSTRAP_MIRROR}"
	./bin/spack mirror add local "file://${BOOTSTRAP_MIRROR}"
fi

test "${BOOTSTRAP_CONFIG_OS}" = "$(bootstrap_get_os)" || exit 1

# Force recreating the compiler configuration since it might have changed
./bin/spack compiler remove "${BOOTSTRAP_CONFIG_OS_COMPILER}" || true
./bin/spack compiler find

# Keep in sync with packages.yaml and modules.yaml
bootstrap_install_compiler gcc@15 "${BOOTSTRAP_CONFIG_OS_COMPILER}"
# CUDA requires an older GCC
bootstrap_install_compiler "${BOOTSTRAP_CONFIG_CUDA_COMPILER}" "${BOOTSTRAP_CONFIG_OS_COMPILER}"

# Modules might not be installed system-wide
bootstrap_install environment-modules

if test "${BOOTSTRAP_CONFIG_OS}" = 'centos8' -o "${BOOTSTRAP_CONFIG_OS}" = 'rocky8'
then
	# man in CentOS/Rocky Linux 8 cannot handle a long MANPATH
	bootstrap_install man-db
fi

# MPI
bootstrap_install mpich

# I/O
bootstrap_install adios2
bootstrap_install fio
bootstrap_install hdf5
bootstrap_install libfuse
bootstrap_install netcdf-c

# Tracing
bootstrap_install cube
bootstrap_install likwid
bootstrap_install otf
bootstrap_install otf2
bootstrap_install scalasca
bootstrap_install scorep

# Compression
bootstrap_install c-blosc
bootstrap_install lz4
bootstrap_install lzma
bootstrap_install lzo
bootstrap_install snappy
bootstrap_install zfp
bootstrap_install zstd

# Math
bootstrap_install gsl
bootstrap_install netlib-scalapack
bootstrap_install octave
bootstrap_install openblas

# Development
bootstrap_install autoconf
bootstrap_install automake
bootstrap_install bison
bootstrap_install boost
bootstrap_install cmake
bootstrap_install doxygen
bootstrap_install flex
bootstrap_install glib
bootstrap_install hwloc
bootstrap_install intel-tbb
bootstrap_install json-c
bootstrap_install libtool
bootstrap_install m4
bootstrap_install meson
bootstrap_install ninja
bootstrap_install pkgconf
bootstrap_install qt-base

# Database
bootstrap_install mariadb-c-client
bootstrap_install postgresql

# Tools
bootstrap_install emacs
bootstrap_install gdb
bootstrap_install git
bootstrap_install git-lfs
bootstrap_install hyperfine
bootstrap_install nano
bootstrap_install numactl
bootstrap_install strace
bootstrap_install sysstat
bootstrap_install tmux
bootstrap_install valgrind
bootstrap_install vim

# Languages
bootstrap_install go
# FIXME Julia needs LLVM that does not build with GCC 15.
bootstrap_install julia "${BOOTSTRAP_CONFIG_CUDA_COMPILER}"
bootstrap_install llvm
bootstrap_install perl
bootstrap_install rust

# Visualization
bootstrap_install gnuplot
bootstrap_install graphviz

# Multimedia
bootstrap_install ffmpeg

# Python
bootstrap_install python
bootstrap_install py-flake8
#bootstrap_install py-keras
bootstrap_install py-h5py
bootstrap_install py-jupyterlab
bootstrap_install py-matplotlib
bootstrap_install py-netcdf4
bootstrap_install py-numpy
bootstrap_install py-pandas
bootstrap_install py-pip
bootstrap_install py-requests
bootstrap_install py-scikit-learn
bootstrap_install py-scipy
bootstrap_install py-seaborn
bootstrap_install py-sphinx
#bootstrap_install py-tensorflow
bootstrap_install py-virtualenv

# R
bootstrap_install r

# CUDA
bootstrap_install py-torch "${BOOTSTRAP_CONFIG_CUDA_COMPILER}"

# Remove all unneeded packages
./bin/spack gc --yes-to-all

# Precreate the variables for our hack in setup-env.sh
# FIXME Does not work with more than one OS
./bin/spack --print-shell-vars sh,modules > share/spack/setup-env.vars

# This is required for chaining to work
./bin/spack module tcl refresh --delete-tree --yes-to-all "os=${BOOTSTRAP_CONFIG_OS}"

bootstrap_create_env

if test -n "${BOOTSTRAP_MIRROR}"
then
	# Remove cached downloads, which are also available in the mirror
	./bin/spack clean --downloads
fi
