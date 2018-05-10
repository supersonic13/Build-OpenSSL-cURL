#!/bin/bash

# This script builds openssl+libcurl libraries for the Mac, iOS and tvOS 
#
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL
#

########################################
# EDIT this section to Select Versions #
########################################

OPENSSL="1.0.2o"
LIBCURL="7.58.0"
NGHTTP2="1.24.0"

########################################

# HTTP2 Support?
NOHTTP2="/tmp/no-http2"
rm -f $NOHTTP2

set -o xtrace

usage ()
{
        echo "usage: $0 [-disable-http2]"
        exit 127
}

if [ "$1" == "-h" ]; then
        usage
fi

echo
echo "Building OpenSSL"
cd openssl 
./openssl-build.sh "$OPENSSL"

./openssl-build-android.sh "$OPENSSL"

cd ..


if [ "$1" == "-enable-http2" ]; then
	echo
	echo "Building nghttp2 for HTTP2 support"
	cd nghttp2
	./nghttp2-build.sh "$NGHTTP2"
	cd ..
else 
	touch "$NOHTTP2"
	NGHTTP2="NONE"	
fi

echo
echo "Building Curl"
cd curl
./libcurl-build.sh "$LIBCURL"

./libcurl-build-android.sh "$LIBCURL"

cd ..

echo 
echo "Libraries..."
echo
echo "openssl [$OPENSSL]"
xcrun -sdk iphoneos lipo -info openssl/*/lib/*.a
echo
echo "nghttp2 (rename to libnghttp2.a) [$NGHTTP2]"
xcrun -sdk iphoneos lipo -info nghttp2/lib/*.a
echo
echo "libcurl (rename to libcurl.a) [$LIBCURL]"
xcrun -sdk iphoneos lipo -info curl/*/lib/*.a

echo
ARCHIVE="archive/libcurl-$LIBCURL-openssl-$OPENSSL-nghttp2-$NGHTTP2"
echo "Creating archive in $ARCHIVE..."
mkdir -p "$ARCHIVE"
mkdir -p "$ARCHIVE/Android/curl"
mkdir -p "$ARCHIVE/Android/openssl"

mkdir -p "$ARCHIVE/Apple/curl"
mkdir -p "$ARCHIVE/Apple/openssl"

cp curl/lib/*.a $ARCHIVE
cp -r curl/Android/* $ARCHIVE/Android/curl/
cp -r openssl/Android/* $ARCHIVE/Android/openssl/

cp -r curl/Mac $ARCHIVE/Apple/curl/
cp -r openssl/Mac $ARCHIVE/Apple/openssl/
cp -r curl/iOS $ARCHIVE/Apple/curl/
cp -r openssl/iOS $ARCHIVE/Apple/openssl/
cp -r curl/tvOS $ARCHIVE/Apple/curl/
cp -r openssl/tvOS $ARCHIVE/Apple/openssl/

#cp openssl/iOS/lib/libcrypto.a $ARCHIVE/libcrypto_iOS.a
#cp openssl/tvOS/lib/libcrypto.a $ARCHIVE/libcrypto_tvOS.a
#cp openssl/Mac/lib/libcrypto.a $ARCHIVE/libcrypto_Mac.a
#cp openssl/iOS/lib/libssl.a $ARCHIVE/libssl_iOS.a
#cp openssl/tvOS/lib/libssl.a $ARCHIVE/libssl_tvOS.a
#cp openssl/Mac/lib/libssl.a $ARCHIVE/libssl_Mac.a
#cp nghttp2/lib/*.a $ARCHIVE
echo "Archiving Mac binaries for curl and openssl..."
mv /tmp/curl $ARCHIVE
mv /tmp/openssl $ARCHIVE
curl https://curl.haxx.se/ca/cacert.pem > $ARCHIVE/cacert.pem
$ARCHIVE/curl -V

rm -f $NOHTTP2
