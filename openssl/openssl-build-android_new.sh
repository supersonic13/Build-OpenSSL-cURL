#! /usr/bin/env bash

MINIMUM_ANDROID_SDK_VERSION=16
MINIMUM_ANDROID_64_BIT_SDK_VERSION=21

export ANDROID_NDK_ROOT="/Users/arun/workspace/ndk/android-ndk-r17"

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
	OPENSSL_VERSION="openssl-1.0.1t"
else
	OPENSSL_VERSION="openssl-$VER_NUMBER"
fi

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
	echo "Downloading ${OPENSSL_VERSION}.tar.gz"
	curl -LO https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
	echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"


(cd ${OPENSSL_VERSION};

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

OPENSSL_CONFIGURE_OPTIONS=""


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
 ./Configure dist

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
	 OUTPUT_DIR="${ANDROID_LIB_ROOT}/openssl-${TARGET_PLATFORM}"
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

     RANLIB=${TOOLCHAIN_PREFIX}-ranlib \
           AR=${TOOLCHAIN_PREFIX}-ar \
           CC=${TOOLCHAIN_PREFIX}-gcc \
           ./Configure ${CONFIGURE_ARCH} \
           -D__ANDROID_API__=${ANDROID_API_VERSION} \
           ${OPENSSL_CONFIGURE_OPTIONS}

     if [ $? -ne 0 ]; then
         echo "Error executing:./Configure ${CONFIGURE_ARCH} ${OPENSSL_CONFIGURE_OPTIONS}"
         exit 1
     fi

     make clean
     make

     if [ $? -ne 0 ]; then
         echo "Error executing make for platform:${TARGET_PLATFORM}"
         exit 1
     fi

     cp libcrypto.a "${OUTPUT_DIR}/lib"	#${ANDROID_LIB_ROOT}/openssl-${PLATFORM_OUTPUT_DIR}
     cp libssl.a "${OUTPUT_DIR}/lib"	#${ANDROID_LIB_ROOT}/openssl-${PLATFORM_OUTPUT_DIR}
	 cp -r include "${OUTPUT_DIR}/"
 done
)
