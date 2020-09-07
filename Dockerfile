##
# osgeo/gdal:alpine-small

# This file is available at the option of the licensee under:
# Public domain
# or licensed under X/MIT (LICENSE.TXT) Copyright 2019 Even Rouault <even.rouault@spatialys.com>
# This file is a copy of "https://github.com/OSGeo/gdal", modified for using it with Python 3 and with GDAL 3.

FROM alpine as builder

# Derived from osgeo/proj by Howard Butler <howard@hobu.co>
LABEL maintainer="Even Rouault <even.rouault@spatialys.com>"

# Setup build env for PROJ
RUN apk add --no-cache wget curl unzip make libtool autoconf automake pkgconfig g++ sqlite sqlite-dev

# For GDAL
RUN apk add --no-cache \
    linux-headers \
    curl-dev tiff-dev \
    zlib-dev zstd-dev \
    libjpeg-turbo-dev libpng-dev openjpeg-dev libwebp-dev expat-dev \
    postgresql-dev \
    && mkdir -p /build_thirdparty/usr/lib

# Build geos
ARG GEOS_VERSION=3.8.1
RUN if test "${GEOS_VERSION}" != ""; then ( \
    wget -q http://download.osgeo.org/geos/geos-${GEOS_VERSION}.tar.bz2 \
    && tar xjf geos-${GEOS_VERSION}.tar.bz2  \
    && rm -f geos-${GEOS_VERSION}.tar.bz2 \
    && cd geos-${GEOS_VERSION} \
    && ./configure --prefix=/usr --disable-static \
    && make -j$(nproc) \
    && make install \
    && cp -P /usr/lib/libgeos*.so* /build_thirdparty/usr/lib \
    && for i in /build_thirdparty/usr/lib/*; do strip -s $i 2>/dev/null || /bin/true; done \
    && cd .. \
    && rm -rf geos-${GEOS_VERSION} \
    ); fi

# Build PROJ
ARG PROJ_VERSION=7.1.1
RUN mkdir proj \
    && wget -q https://github.com/OSGeo/PROJ/archive/${PROJ_VERSION}.tar.gz -O - \
        | tar xz -C proj --strip-components=1 \
    && cd proj \
    && ./autogen.sh \
    && ./configure --prefix=/usr --disable-static --enable-lto \
    && make -j$(nproc) \
    && make install \
    && make install DESTDIR="/build_proj" \
    && cd .. \
    && rm -rf proj \
    && for i in /build_proj/usr/lib/*; do strip -s $i 2>/dev/null || /bin/true; done \
    && for i in /build_proj/usr/bin/*; do strip -s $i 2>/dev/null || /bin/true; done

# Build GDAL
ARG GDAL_VERSION=3.1.3
ARG GDAL_RELEASE_DATE
RUN if test "${GDAL_VERSION}" = "master"; then \
        export GDAL_VERSION=$(curl -Ls https://api.github.com/repos/OSGeo/gdal/commits/HEAD -H "Accept: application/vnd.github.VERSION.sha"); \
        export GDAL_RELEASE_DATE=$(date "+%Y%m%d"); \
    fi \
    && export GDAL_EXTRA_ARGS="" \
    && if test "${GEOS_VERSION}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-geos ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${XERCESC_VERSION}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-xerces ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${HDF4_VERSION}" != ""; then \
        apk add --no-cache portablexdr-dev \
        && export LDFLAGS="-lportablexdr ${LDFLAGS}" \
        && export GDAL_EXTRA_ARGS="--with-hdf4 ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${HDF5_VERSION}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-hdf5 ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${NETCDF_VERSION}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-netcdf ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${SPATIALITE_VERSION}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-spatialite ${GDAL_EXTRA_ARGS}"; \
    fi \
    && if test "${POPPLER_DEV}" != ""; then \
        export GDAL_EXTRA_ARGS="--with-poppler ${GDAL_EXTRA_ARGS}"; \
    fi \
    && echo ${GDAL_EXTRA_ARGS} \
    && mkdir gdal \
    && wget -q https://github.com/OSGeo/gdal/archive/v${GDAL_VERSION}.tar.gz -O - \
        | tar xz -C gdal --strip-components=1 \
    && cd gdal/gdal \
    && ./configure --prefix=/usr --without-libtool \
    --with-hide-internal-symbols \
    --with-proj=/usr \
    --with-libtiff=internal --with-rename-internal-libtiff-symbols \
    --with-geotiff=internal --with-rename-internal-libgeotiff-symbols \
    # --enable-lto
    ${GDAL_EXTRA_ARGS} \
    && make -j$(nproc) \
    && make install DESTDIR="/build" \
    && cd ../.. \
    && rm -rf gdal \
    && mkdir -p /build_gdal_version_changing/usr/include \
    && mv /build/usr/lib                    /build_gdal_version_changing/usr \
    && mv /build/usr/include/gdal_version.h /build_gdal_version_changing/usr/include \
    && mv /build/usr/bin                    /build_gdal_version_changing/usr \
    && for i in /build_gdal_version_changing/usr/lib/*; do strip -s $i 2>/dev/null || /bin/true; done \
    && for i in /build_gdal_version_changing/usr/bin/*; do strip -s $i 2>/dev/null || /bin/true; done \
    # Remove resource files of uncompiled drivers
    && (for i in \
            # BAG driver
            /build/usr/share/gdal/bag*.xml \
            # unused
            /build/usr/share/gdal/*.svg \
            # unused
            /build/usr/share/gdal/*.png \
            # GMLAS driver
            /build/usr/share/gdal/gmlas* \
            # netCDF driver
            /build/usr/share/gdal/netcdf_config.xsd \
       ;do rm $i; done)

# Build final image
FROM python:alpine as runner

RUN apk add --no-cache \
        libstdc++ sqlite-libs libcurl tiff zlib zstd-libs \
        libjpeg-turbo libpng openjpeg libwebp expat libpq \
    # libturbojpeg.so is not used by GDAL. Only libjpeg.so*
    && rm -f /usr/lib/libturbojpeg.so* \
    # Only libwebp.so is used by GDAL
    && rm -f /usr/lib/libwebpmux.so* /usr/lib/libwebpdemux.so* /usr/lib/libwebpdecoder.so*

# Order layers starting with less frequently varying ones
COPY --from=builder  /build_thirdparty/usr/ /usr/

# COPY --from=builder  /build_projgrids/usr/ /usr/

COPY --from=builder  /build_proj/usr/share/proj/ /usr/share/proj/
COPY --from=builder  /build_proj/usr/include/ /usr/include/
COPY --from=builder  /build_proj/usr/bin/ /usr/bin/
COPY --from=builder  /build_proj/usr/lib/ /usr/lib/

COPY --from=builder  /build/usr/share/gdal/ /usr/share/gdal/
COPY --from=builder  /build/usr/include/ /usr/include/
COPY --from=builder  /build_gdal_version_changing/usr/ /usr/

RUN set -ex \
  && apk add --no-cache --virtual .build-deps build-base gfortran \
  # Install python packages
  && pip install --no-cache-dir numpy \
  && pip install --no-cache-dir GDAL=="`gdal-config --version`.*" \
  # Remove all non-required files
  && apk del .build-deps \
  && rm -rf /tmp/*
