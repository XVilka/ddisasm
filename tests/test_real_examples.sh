
dir="../real_world_examples/"

#get the real examples
if [ ! -d "$dir" ]; then
  ./fetch_real_examples.sh
fi

pushd ../bin/
compilers=(
    "gcc"
 #   "gcc8"
    "clang"
);

cpp_compilers=(
    "g++"
#    "g++8"
    "clang++"
);

optimizations=(
    ""
    "-O1"
    "-O2"
    "-O3"
    "-Os"
);

examples=(
    "grep-2.5.4 src/grep -lpcre"
    "gzip-1.2.4 gzip"
    "bar-1.11.0 bar"
    "conflict-6.0 conflict"
    "ed-0.2/ ed"
    "ed-0.9/ ed"
    "marst-2.4/ marst"
    "units-1.85/ units -lm -lreadline -lncurses"
    "doschk-1.1/ doschk"
    "bool-0.2/ src/bool"
    "m4-1.4.4/ src/m4"
    "patch-2.6.1/ src/patch"
    "enscript-1.6.1/ src/enscript -lm"
    "bison-2.1/ src/bison"
    "sed-4.2/ sed/sed"
    "flex-2.5.4/ flex"
    "make-3.80/ make"
    "rsync-3.0.7/ rsync"
    "gperf-3.0.3/ src/gperf  g++"
    "re2c-0.13.5/ re2c g++"
    "lighttpd-1.4.18/ src/lighttpd -rdynamic -lpcre -ldl"
    "tar-1.29/ src/tar"
);


strip=""
if [[ $# > 0 && $1 == "-strip" ]]; then
    strip="-strip"
    shift
fi

stir=""
if [[ $# > 0 && $1 == "-stir" ]]; then
    stir="-stir"
    shift
fi
error=0
success=0
this_directory=$(pwd)

for ((i = 0; i < ${#examples[@]}; i++)); do
    j=0
    directory=($sentence${examples[$i]})
    cd $dir$directory
    unset CC
    unset CFLAGS
    ./configure
    cd $this_directory
    for compiler in "${compilers[@]}"; do
	export CC=$compiler
	export CXX=${cpp_compilers[$j]}
	for optimization in  "${optimizations[@]}"; do
	    export CFLAGS="$optimization"
	    echo "#Example ${examples[$i]} with $CC/$CXX $optimization"
	    if !(bash ./reassemble_and_test.sh $strip $stir $dir${examples[$i]}) then
	       ((error++))
	       else
		   ((success++))
	    fi
	done
		((j++))
    done
done


echo "$success/$((error+success)) tests succeed"

if (( $error > 0 )); then
    echo "$error tests failed"
    exit 1
fi
