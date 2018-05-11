#! /usr/bin/env bash

MINIMUM_ANDROID_SDK_VERSION=21
MINIMUM_ANDROID_64_BIT_SDK_VERSION=21

export ANDROID_NDK_ROOT="/Users/arun/workspace/ndk/android-ndk-r17"

usage ()
{
	echo "usage: $0 -v 7.50.1"
	trap - INT TERM EXIT
	exit 127
}

VER_NUMBER=""
verbose=1

while getopts "h?v:a:q" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
	v)	VER_NUMBER=$OPTARG
		;;
	a)	TARGET_ARCH=$OPTARG
		;;
    q)  verbose=0
        ;;
    esac
done

if [ "$verbose" == 1 ]; then
	set -o xtrace
fi

if [ "$VER_NUMBER" == "" ]; then
	CURL_VERSION="curl-7.50.1"
else
	CURL_VERSION="curl-$VER_NUMBER"
fi

rm -rf "${CURL_VERSION}"

if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

OPENSSL="${PWD}/../openssl/Android"



(cd ${CURL_VERSION};

 if [ ! ${MINIMUM_ANDROID_SDK_VERSION} ]; then
     echo "MINIMUM_ANDROID_SDK_VERSION was not provided, include and rerun"
     exit 1
 fi

 if [ ! ${MINIMUM_ANDROID_64_BIT_SDK_VERSION} ]; then
     echo "MINIMUM_ANDROID_64_BIT_SDK_VERSION was not provided, include and rerun"
     exit 1
 fi

 if [ ! ${ANDROID_NDK_ROOT} ]; then
     echo "ANDROID_NDK_ROOT environment variable not set, set and rerun"
     exit 1
 fi

 #ANDROID_LIB_ROOT=../android-libs
 ANDROID_LIB_ROOT=../Android
 ANDROID_TOOLCHAIN_DIR=/tmp/openssl-android-toolchain
 #OPENSSL_CONFIGURE_OPTIONS="no-krb5 no-idea no-camellia \
		#no-seed no-bf no-cast no-rc2 no-rc4 no-rc5 no-md2 \
		#no-md4 no-ripemd no-rsa no-ecdh no-sock no-ssl2 no-ssl3 \
		#no-dsa no-dh no-ec no-ecdsa no-tls1 no-pbe no-pkcs \
		#no-tlsext no-pem no-rfc3779 no-whirlpool no-ui no-srp \
		#no-ssltrace no-tlsext no-mdc2 no-ecdh no-engine \
		#no-tls2 no-srtp -fPIC"

ANDROID_SYSROOT="${ANDROID_TOOLCHAIN_DIR}/sysroot"

#CURL_CONFIGURE_OPTIONS="--disable-ldap --disable-ldaps \
	#--with-zlib --disable-ftp --disable-gopher \
	#--disable-imap --disable-ldap --disable-ldaps --disable-pop3 \
	#--disable-rtsp --disable-smtp --disable-telnet \
	#--disable-tftp --without-gnutls --without-libidn --without-librtmp --disable-dict \
	#--enable-ipv6 --enable-static \
	#--with-ssl=${OPENSSL}/openssl-${ABI} \
	#--with-sysroot=${ANDROID_SYSROOT}"

CURL_CONFIGURE_OPTIONS=""

 HOST_INFO=`uname -a`
 case ${HOST_INFO} in
     Darwin*)
         TOOLCHAIN_SYSTEM=darwin-x86
         ;;
     Linux*)
         if [[ "${HOST_INFO}" == *i686* ]]
         then
             TOOLCHAIN_SYSTEM=linux-x86
         else
             TOOLCHAIN_SYSTEM=linux-x86_64
         fi
         ;;
     *)
         echo "Toolchain unknown for host system"
         exit 1
         ;;
 esac

 rm -rf ${ANDROID_LIB_ROOT}
 #git clean -dfx && git checkout -f
# ./Configure dist

 #for SQLCIPHER_TARGET_PLATFORM in armeabi armeabi-v7a x86 x86_64 arm64-v8a
 for TARGET_PLATFORM in armeabi armeabi-v7a 
 do
     echo "Building for libcrypto.a for ${TARGET_PLATFORM}"
     case "${TARGET_PLATFORM}" in
         armeabi)
             TOOLCHAIN_ARCH=arm
             TOOLCHAIN_PREFIX=arm-linux-androideabi
             CONFIGURE_ARCH="android"
             PLATFORM_OUTPUT_DIR=armeabi
             ANDROID_API_VERSION=${MINIMUM_ANDROID_SDK_VERSION}
             ;;
         armeabi-v7a)
             TOOLCHAIN_ARCH=arm
             TOOLCHAIN_PREFIX=arm-linux-androideabi
             CONFIGURE_ARCH="android -march=armv7-a"
             PLATFORM_OUTPUT_DIR=armeabi-v7a
             ANDROID_API_VERSION=${MINIMUM_ANDROID_SDK_VERSION}
             ;;
         x86)
             TOOLCHAIN_ARCH=x86
             TOOLCHAIN_PREFIX=i686-linux-android
             CONFIGURE_ARCH="android-x86"
             PLATFORM_OUTPUT_DIR=x86
             ANDROID_API_VERSION=${MINIMUM_ANDROID_SDK_VERSION}
             ;;
         x86_64)
             TOOLCHAIN_ARCH=x86_64
             TOOLCHAIN_PREFIX=x86_64-linux-android
             CONFIGURE_ARCH="android64"
             PLATFORM_OUTPUT_DIR=x86_64
             ANDROID_API_VERSION=${MINIMUM_ANDROID_64_BIT_SDK_VERSION}
             ;;
         arm64-v8a)
             TOOLCHAIN_ARCH=arm64
             TOOLCHAIN_PREFIX=aarch64-linux-android
             CONFIGURE_ARCH="android64-aarch64"
             PLATFORM_OUTPUT_DIR=arm64-v8a
             ANDROID_API_VERSION=${MINIMUM_ANDROID_64_BIT_SDK_VERSION}
             ;;
         *)
             echo "Unsupported build platform:${TARGET_PLATFORM}"
             exit 1
     esac

     rm -rf ${ANDROID_TOOLCHAIN_DIR}
	 OUTPUT_DIR="${ANDROID_LIB_ROOT}/curl-${TARGET_PLATFORM}"
     mkdir -p "${OUTPUT_DIR}/lib"
     #mkdir -p "${OUTPUT_DIR}/"
     python ${ANDROID_NDK_ROOT}/build/tools/make_standalone_toolchain.py \
            --arch ${TOOLCHAIN_ARCH} \
            --api ${ANDROID_API_VERSION} \
            --install-dir ${ANDROID_TOOLCHAIN_DIR}
#
#	 --unified-headers

     if [ $? -ne 0 ]; then
         echo "Error executing make_standalone_toolchain.py for ${TOOLCHAIN_ARCH}"
         exit 1
     fi

     export PATH=${ANDROID_TOOLCHAIN_DIR}/bin:$PATH
     export CROSS_SYSROOT=${ANDROID_TOOLCHAIN_DIR}/sysroot

	 export CROSS_COMPILE=$TOOLCHAIN_PREFIX
	 export CPPFLAGS="-I${OPENSSL}/openssl-${TARGET_PLATFORM}/include"
	 export LDFLAGS="-L${OPENSSL}/openssl-${TARGET_PLATFORM}"
	 export LIBS="-lssl -lcrypto"

	 export AS=${TOOLCHAIN_PREFIX}-as
	 export LD=${TOOLCHAIN_PREFIX}-ld
	 export NM=${TOOLCHAIN_PREFIX}-nm

     #RANLIB=${TOOLCHAIN_PREFIX}-ranlib \
           #AR=${TOOLCHAIN_PREFIX}-ar \
           #CC=${TOOLCHAIN_PREFIX}-gcc \
		   #CXX=${TOOLCHAIN_PREFIX}-g++ \
           #./configure \
		   #--host=${CROSS_COMPILE} \
           #${CURL_CONFIGURE_OPTIONS}

 	 RANLIB=${TOOLCHAIN_PREFIX}-ranlib \
           AR=${TOOLCHAIN_PREFIX}-ar \
           CC=${TOOLCHAIN_PREFIX}-gcc \
		   CXX=${TOOLCHAIN_PREFIX}-g++ \
			./configure --prefix="/tmp/${CURL_VERSION}-Android-${PLATFORM_OUTPUT_DIR}" \
			  --with-random=/dev/urandom \
			  --with-sysroot=${CROSS_SYSROOT} \
         	  --host=${TOOLCHAIN_PREFIX} \
              --with-ssl=${OPENSSL}/openssl-${ABI} \
              --enable-ipv6 \
              --enable-static \
              --enable-threaded-resolver \
              --disable-dict \
              --disable-gopher \
              --disable-ldap --disable-ldaps \
              --disable-manual \
              --disable-pop3 --disable-smtp --disable-imap \
              --disable-rtsp \
              --disable-shared \
              --disable-smb \
              --disable-telnet \
              --disable-verbose \
			 &> "configure-curl.log" 

     if [ $? -ne 0 ]; then
         echo "Error executing:./Configure ${CONFIGURE_ARCH} ${CURL_CONFIGURE_OPTIONS}"
         exit 1
     fi

     make clean
     make

     if [ $? -ne 0 ]; then
         echo "Error executing make for platform:${TARGET_PLATFORM}"
         exit 1
     fi

     cp curl.a "${OUTPUT_DIR}/lib"	
     #cp libssl.a "${OUTPUT_DIR}/lib"	
	 cp -r include "${OUTPUT_DIR}/"
 done
)













## HTTP2 support
#NOHTTP2="/tmp/no-http2"
#if [ ! -f "$NOHTTP2" ]; then
	## nghttp2 will be in ../nghttp2/{Platform}/{arch}
	#NGHTTP2="${PWD}/../nghttp2"  
#fi

#if [ ! -z "$NGHTTP2" ]; then 
	#echo "Building with HTTP2 Support (nghttp2)"
#else
	#echo "Building without HTTP2 Support (nghttp2)"
	#NGHTTP2CFG=""
	#NGHTTP2LIB=""
#fi








#configureAndroid()
#{
	#ARCH=$1; ABI=$2; CLANG=${3:-""};
	#TOOLS_ROOT="/tmp/${CURL_VERSION}-Android-${ABI}"
	##TOOLCHAIN_ROOT=${TOOLS_ROOT}/${ABI}-android-toolchain
	#TOOLCHAIN_ROOT=/tmp/openssl-android-toolchain

	#if [ "$ARCH" == "android" ]; then
		#export ARCH_FLAGS="-mthumb"
		#export ARCH_LINK=""
		#export TOOL="arm-linux-androideabi"
		#NDK_FLAGS="--arch=arm"
	#elif [ "$ARCH" == "android-armeabi" ]; then
		#export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb -mfpu=neon"
		#export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"
		#export TOOL="arm-linux-androideabi"
		#NDK_FLAGS="--arch=arm"
	#elif [ "$ARCH" == "android64-aarch64" ]; then
		#export ARCH_FLAGS=""
		#export ARCH_LINK=""
		#export TOOL="aarch64-linux-android"
		#NDK_FLAGS="--arch=arm64"
	#elif [ "$ARCH" == "android-x86" ]; then
		#export ARCH_FLAGS="-march=i686 -mtune=intel -msse3 -mfpmath=sse -m32"
		#export ARCH_LINK=""
		#export TOOL="i686-linux-android"
		#NDK_FLAGS="--arch=x86"
	#elif [ "$ARCH" == "android64" ]; then
		#export ARCH_FLAGS="-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel"
		#export ARCH_LINK=""
		#export TOOL="x86_64-linux-android"
		#NDK_FLAGS="--arch=x86_64"
	#elif [ "$ARCH" == "android-mips" ]; then
		#export ARCH_FLAGS=""
		#export ARCH_LINK=""
		#export TOOL="mipsel-linux-android"
		#NDK_FLAGS="--arch=mips"
	#elif [ "$ARCH" == "android-mips64" ]; then
		#export ARCH="linux64-mips64"
		#export ARCH_FLAGS=""
		#export ARCH_LINK=""
		#export TOOL="mips64el-linux-android"
		#NDK_FLAGS="--arch=mips64"
	#fi;

	#[ -d ${TOOLCHAIN_ROOT} ] || python $NDK/build/tools/make_standalone_toolchain.py \
                                     #--api ${ANDROID_API} \
                                     #--stl libc++ \
                                     #--install-dir=${TOOLCHAIN_ROOT} \
                                     #$NDK_FLAGS

	#export TOOLCHAIN_PATH=${TOOLCHAIN_ROOT}/bin
	#export NDK_TOOLCHAIN_BASENAME=${TOOLCHAIN_PATH}/${TOOL}
	#export SYSROOT=${TOOLCHAIN_ROOT}/sysroot
	#export CROSS_SYSROOT=$SYSROOT
	#if [ -z "${CLANG}" ]; then
		#export CC=${NDK_TOOLCHAIN_BASENAME}-gcc
		#export CXX=${NDK_TOOLCHAIN_BASENAME}-g++
	#else
		#export CC=${NDK_TOOLCHAIN_BASENAME}-clang
		#export CXX=${NDK_TOOLCHAIN_BASENAME}-clang++
	#fi;
	#export LINK=${CXX}
	#export LD=${NDK_TOOLCHAIN_BASENAME}-ld
	#export AR=${NDK_TOOLCHAIN_BASENAME}-ar
	#export RANLIB=${NDK_TOOLCHAIN_BASENAME}-ranlib
	#export STRIP=${NDK_TOOLCHAIN_BASENAME}-strip
	#export CPPFLAGS=${CPPFLAGS:-""}
	#export LIBS=${LIBS:-""}
	##export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -D__ANDROID_API__=${ANDROID_API}"
	#export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
	#export CXXFLAGS="${CFLAGS} -std=c++11 -frtti -fexceptions -D__ANDROID_API__=${ANDROID_API}"
	#export LDFLAGS="${ARCH_LINK}"
	#echo "**********************************************"
	#echo "use ANDROID_API=${ANDROID_API}"
	#echo "use NDK=${NDK}"
	#echo "export ARCH=${ARCH}"
	#echo "export NDK_TOOLCHAIN_BASENAME=${NDK_TOOLCHAIN_BASENAME}"
	#echo "export SYSROOT=${SYSROOT}"
	#echo "export CC=${CC}"
	#echo "export CXX=${CXX}"
	#echo "export LINK=${LINK}"
	#echo "export LD=${LD}"
	#echo "export AR=${AR}"
	#echo "export RANLIB=${RANLIB}"
	#echo "export STRIP=${STRIP}"
	#echo "export CPPFLAGS=${CPPFLAGS}"
	#echo "export CFLAGS=${CFLAGS}"
	#echo "export CXXFLAGS=${CXXFLAGS}"
	#echo "export LDFLAGS=${LDFLAGS}"
	#echo "export LIBS=${LIBS}"
	#echo "**********************************************"
#}

#buildAndroid()
#{
	#ARCH=$1; ABI=$2;

	#pushd . > /dev/null
	#cd "${CURL_VERSION}"

	### https://github.com/n8fr8/orbot/issues/92 - OpenSSL doesn't support compilation with clang (on Android) yet. You'll have to use GCC
	##configureAndroid $ARCH $ABI "clang"
	#configureAndroid $ARCH $ABI

	## Copy the correct SSL libs
	#cp ${OPENSSL}/openssl-${ABI}/lib/libssl.a ${SYSROOT}/usr/lib
	#cp ${OPENSSL}/openssl-${ABI}/lib/libcrypto.a ${SYSROOT}/usr/lib
	#cp -r ${OPENSSL}/openssl-${ABI}/include/openssl ${SYSROOT}/usr/include

	##if [ ! -z "$NGHTTP2" ]; then 
		##NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		##NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	##fi
	## export add to LDFLAGS="${NGHTTP2LIB}"

	#./configure --prefix="/tmp/${CURL_VERSION}-Android-${ABI}" \
			  #--with-random=/dev/urandom \
			  #--with-sysroot=${SYSROOT} \
               #--host=${TOOL} \
              #--with-ssl=${OPENSSL}/openssl-${ABI} \
              #--enable-ipv6 \
              #--enable-static \
              #--enable-threaded-resolver \
              #--disable-dict \
              #--disable-gopher \
              #--disable-ldap --disable-ldaps \
              #--disable-manual \
              #--disable-pop3 --disable-smtp --disable-imap \
              #--disable-rtsp \
              #--disable-shared \
              #--disable-smb \
              #--disable-telnet \
              #--disable-verbose \
			  #&> "/tmp/${CURL_VERSION}-Android-${ABI}.log"

	##export LIBS="-lssl -lcrypto"
	##export LDFLAGS="-arch ${ARCH} -isysroot ${SYSROOT} -L${OPENSSL}/openssl-${ABI}/lib"

	#PATH=$TOOLCHAIN_PATH:$PATH

	#make clean >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1

	#if make -j4 >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1; then
		#make install >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1
		
		#make clean >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1
	#fi

	#popd > /dev/null


	#OUTPUT_ROOT=Android/curl-${ABI}
	#[ -d ${OUTPUT_ROOT}/include ] || mkdir -p ${OUTPUT_ROOT}/include

	#cp -r "/tmp/${CURL_VERSION}-Android-${ABI}/include/curl" ${OUTPUT_ROOT}/include

	#[ -d ${OUTPUT_ROOT}/lib ] || mkdir -p ${OUTPUT_ROOT}/lib
	#cp "/tmp/${CURL_VERSION}-Android-${ABI}/lib/libcurl.a" ${OUTPUT_ROOT}/lib

#}

#buildAndroidLibsOnly()
#{
	#mkdir -p Android/lib
	#mkdir -p Android/include/openssl/


	##ARCHS=("android" "android-armeabi" "android64-aarch64" "android-x86" "android64" "android-mips" "android-mips64")
	##ABIS=("armeabi" "armeabi-v7a" "arm64-v8a" "x86" "x86_64" "mips" "mips64")

	#echo "Building Android libraries"
	#buildAndroid "android" "armeabi"
	#buildAndroid "android-armeabi" "armeabi-v7a"
	##buildAndroid "android64-aarch64" "arm64-v8a"
	##buildAndroid "android-x86" "x86"
	##buildAndroid "android64" "x86_64"
	
	##buildAndroid "android-mips" "mips"
	##buildAndroid "android-mips64" "mips64"
#}

#echo "Cleaning up"
#rm -rf include/curl/* lib/*

#mkdir -p lib
#mkdir -p include/curl/

#rm -rf "/tmp/${CURL_VERSION}-*"
#rm -rf "/tmp/${CURL_VERSION}-*.log"

#rm -rf "${CURL_VERSION}"

#if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	#echo "Downloading ${CURL_VERSION}.tar.gz"
	#curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
#else
	#echo "Using ${CURL_VERSION}.tar.gz"
#fi

#echo "Unpacking curl"
#tar xfz "${CURL_VERSION}.tar.gz"

#buildAndroidLibsOnly

#echo "Cleaning up"
#rm -rf /tmp/${CURL_VERSION}-*
#rm -rf ${CURL_VERSION}
#echo "Checking libraries"
##xcrun -sdk iphoneos lipo -info lib/*.a

##reset trap
#trap - INT TERM EXIT

#echo "Done"
