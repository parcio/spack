#!/bin/sh

set -e

SELF_PATH="$(readlink --canonicalize-existing -- "$0")"
SELF_DIR="${SELF_PATH%/*}"
SELF_BASE="${SELF_PATH##*/}"

usage ()
{
	printf 'Usage: %s [prepare|build]\n' "${SELF_BASE}"
	exit 1
}

BOOTSTRAP_COMPILER=''
BOOTSTRAP_MIRROR="$(realpath "$(pwd)/../spack-mirror")"
#BOOTSTRAP_MIRROR=''
BOOTSTRAP_OS=''
BOOTSTRAP_PHASE=''

bootstrap_get_os ()
{
	test -f /etc/os-release

	(
		. /etc/os-release
		printf '%s%s' "${ID}" "${VERSION_ID}"
	)
}

bootstrap_in_phase ()
{
	local phase

	phase="$1"

	test -n "${phase}" || return 1
	test "${phase}" = 'prepare' -o "${phase}" = 'build' || return 1

	if test -z "${BOOTSTRAP_PHASE}" -o "${BOOTSTRAP_PHASE}" = "${phase}"
	then
		return 0
	else
		return 1
	fi
}

bootstrap_apply_pr ()
{
	local pr

	pr="$1"

	test -n "${pr}" || return 1

	rm --force "${pr}.diff"
	curl --fail --location --remote-name "https://github.com/spack/spack/pull/${pr}.diff"
	git apply --verbose "${pr}.diff"
}

bootstrap_install ()
{
	if bootstrap_in_phase prepare
	then
		if test -n "${BOOTSTRAP_MIRROR}"
		then
			echo "Mirroring $*"
			./bin/spack mirror create --directory "${BOOTSTRAP_MIRROR}" --dependencies "$@" %gcc@12.3.0
		fi
	fi

	if bootstrap_in_phase build
	then
		echo "Installing $*"
		./bin/spack install "$@"
	fi
}

bootstrap_install_compiler ()
{
	local location

	bootstrap_install "$@"

	if bootstrap_in_phase build
	then
		location="$(./bin/spack location --install-dir "$@")"
		./bin/spack compiler find "${location}"
	fi
}

bootstrap_module_load ()
{
	local module

	module="$1"

	test -n "${module}" || return 1

	printf 'module load %s > /dev/null || echo "Could not load %s"\n' "${module}" "${module}"
}

bootstrap_create_env ()
{
	local env_file

	env_file='../env.sh'

	{
		printf 'test "$(id -u)" -eq 0 && return 0\n'
		printf '\n'
		printf 'export SPACK_DISABLE_LOCAL_CONFIG=1\n'
		printf 'export SLURM_OVERLAP=1\n'
		printf 'export SLURM_MPI_TYPE=pmi2\n'
		# FIXME PMIx prints warning about missing Munge (https://github.com/open-mpi/ompi/issues/11557)
		#printf 'export PMIX_MCA_psec=^munge\n'
		printf '\n'
		printf '. %s/share/spack/setup-env.sh\n' "$(pwd)"
		printf '\n'
		bootstrap_module_load man-db
		bootstrap_module_load gcc
		bootstrap_module_load python
		bootstrap_module_load mpich
		printf '\n'
		bootstrap_module_load gdb
		bootstrap_module_load git
		bootstrap_module_load nano
		bootstrap_module_load valgrind
		bootstrap_module_load vim
	} > "${env_file}"
}

BOOTSTRAP_PHASE="$1"

test -z "${BOOTSTRAP_PHASE}" -o "${BOOTSTRAP_PHASE}" = 'prepare' -o "${BOOTSTRAP_PHASE}" = 'build' || usage

if test -f /etc/profile.d/modules.sh
then
	. /etc/profile.d/modules.sh
fi

module purge || true

cd spack

export SPACK_DISABLE_LOCAL_CONFIG=1

if bootstrap_in_phase prepare
then
	git checkout --force

	# FIXME Find a better way to do this
	git apply --verbose ../patches/env.patch

	#bootstrap_apply_pr xyz

	rm --force --recursive "${HOME}/.spack"

	rm --force etc/spack/mirrors.yaml

	cp ../config/concretizer.yaml etc/spack
	cp ../config/config.yaml etc/spack
	cp ../config/modules.yaml etc/spack
	cp ../config/packages.yaml etc/spack

	if test -n "${BOOTSTRAP_MIRROR}"
	then
		mkdir --parents "${BOOTSTRAP_MIRROR}"
		./bin/spack mirror add local "file://${BOOTSTRAP_MIRROR}"
	fi
fi

BOOTSTRAP_OS="$(bootstrap_get_os)"

case "${BOOTSTRAP_OS}" in
	centos8)
		BOOTSTRAP_COMPILER='gcc@8.5.0'
		;;
	rocky9.*)
		BOOTSTRAP_COMPILER='gcc@11.4.1'
		;;
esac

# Force recreating the compiler configuration since it might be different from the prepare phase
./bin/spack compiler remove "${BOOTSTRAP_COMPILER}"

# Keep in sync with packages.yaml and modules.yaml
bootstrap_install_compiler gcc@12.3.0 "%${BOOTSTRAP_COMPILER}"

# Modules might not be installed system-wide
bootstrap_install environment-modules target=x86_64

# FIXME man in CentOS 8 cannot handle a long MANPATH
bootstrap_install man-db

# MPI
bootstrap_install mpich

# I/O
bootstrap_install adios
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
bootstrap_install julia
bootstrap_install llvm
bootstrap_install perl
bootstrap_install rust

# Visualization
bootstrap_install gnuplot
bootstrap_install graphviz

# Python
bootstrap_install python
bootstrap_install py-flake8
#bootstrap_install py-keras
bootstrap_install py-h5py
bootstrap_install py-matplotlib
bootstrap_install py-netcdf4
bootstrap_install py-numpy
bootstrap_install py-pandas
bootstrap_install py-pip
bootstrap_install py-poetry
bootstrap_install py-requests
bootstrap_install py-scikit-learn
bootstrap_install py-scipy
bootstrap_install py-seaborn
bootstrap_install py-sphinx
#bootstrap_install py-tensorflow
bootstrap_install py-torch
bootstrap_install py-virtualenv

# R
bootstrap_install r

if bootstrap_in_phase build
then
	# Remove all unneeded packages
	./bin/spack gc --yes-to-all

	# Precreate the variables for our hack in setup-env.sh
	# FIXME Does not work with more than one OS
	#./bin/spack --print-shell-vars sh,modules > share/spack/setup-env.vars

	# This is required for chaining to work
	./bin/spack module tcl refresh --delete-tree --yes-to-all

	bootstrap_create_env

	if test -n "${BOOTSTRAP_MIRROR}"
	then
		# Remove cached downloads, which are also available in the mirror
		./bin/spack clean --downloads
	fi
fi
