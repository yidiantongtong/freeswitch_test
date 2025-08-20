# 多阶段构建优化版
# 第一阶段：构建环境 - 使用官方Debian镜像并解决Docker Hub拉取限制
FROM dragonwell-registry.cn-hangzhou.cr.aliyuncs.com/dragonwell/dragonwell as builder

# 元数据
LABEL maintainer="Andrey Volk <andrey@signalwire.com>"

# 使用阿里云APT源加速国内构建
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list

# 一次性安装所有依赖
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
    git ca-certificates \
    build-essential cmake automake autoconf libtool-bin pkg-config \
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev \
    libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev uuid-dev \
    libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
    libogg-dev libspeex-dev libspeexdsp-dev libldns-dev python3-dev \
    libavformat-dev libswscale-dev libavresample-dev liblua5.2-dev \
    libopus-dev libpq-dev libsndfile1-dev libflac-dev libvorbis-dev \
    libshout3-dev libmpg123-dev libmp3lame-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 克隆所有仓库（使用浅克隆减小体积）
RUN mkdir -p /usr/src/libs && \
    GIT_SSL_NO_VERIFY=1 git clone --depth 1 https://github.com/signalwire/freeswitch /usr/src/freeswitch && \
    GIT_SSL_NO_VERIFY=1 git clone --depth 1 https://github.com/signalwire/libks /usr/src/libs/libks && \
    GIT_SSL_NO_VERIFY=1 git clone --depth 1 https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip && \
    GIT_SSL_NO_VERIFY=1 git clone --depth 1 https://github.com/freeswitch/spandsp /usr/src/libs/spandsp && \
    GIT_SSL_NO_VERIFY=1 git clone --depth 1 https://github.com/signalwire/signalwire-c /usr/src/libs/signalwire-c

# 构建依赖库
WORKDIR /usr/src/libs/libks
RUN cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install

WORKDIR /usr/src/libs/sofia-sip
RUN ./bootstrap.sh && \
    ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no \
    --without-doxygen --disable-stun --prefix=/usr && \
    make -j$(nproc) install

WORKDIR /usr/src/libs/spandsp
RUN ./bootstrap.sh && \
    ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && \
    make -j$(nproc) install

WORKDIR /usr/src/libs/signalwire-c
RUN PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# 启用mod_shout模块
RUN sed -i 's|#formats/mod_shout|formats/mod_shout|' /usr/src/freeswitch/build/modules.conf.in

# 构建FreeSWITCH
WORKDIR /usr/src/freeswitch
RUN ./bootstrap.sh -j && \
    ./configure --prefix=/opt/freeswitch && \
    make -j$(nproc) && \
    make install

# 清理构建环境
RUN rm -rf /usr/src/*

# 第二阶段：运行时环境 - 使用官方Debian镜像
FROM dragonwell-registry.cn-hangzhou.cr.aliyuncs.com/dragonwell/dragonwell

# 使用阿里云APT源
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list

# 安装运行时依赖
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
    libssl1.1 libpcre3 libedit2 libsqlite3-0 libcurl4 libldns2 \
    libogg0 libspeex1 libspeexdsp1 libopus0 libsndfile1 libflac8 libvorbis0a \
    libmpg123-0 libmp3lame0 libavformat58 libswscale5 libavresample4 \
    libpq5 liblua5.2-0 ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制构建结果
COPY --from=builder /opt/freeswitch /opt/freeswitch
COPY --from=builder /etc/freeswitch /etc/freeswitch

# 创建专用用户
RUN groupadd -r freeswitch && \
    useradd -r -g freeswitch -d /opt/freeswitch freeswitch

# 设置权限
RUN chown -R freeswitch:freeswitch /opt/freeswitch /etc/freeswitch && \
    mkdir -p /var/log/freeswitch /var/run/freeswitch && \
    chown -R freeswitch:freeswitch /var/log/freeswitch /var/run/freeswitch

# 设置环境和工作目录
ENV PATH="/opt/freeswitch/bin:${PATH}"
WORKDIR /opt/freeswitch

# 使用非root用户运行
USER freeswitch

# 启动命令
CMD ["freeswitch", "-nonat"]
