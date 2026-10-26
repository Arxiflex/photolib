// Preloaded by tools/offline.sh into a test suite: a connection or datagram to anything but loopback fails with
// ENETUNREACH, and so does DNS, which a loopback resolver would forward; looking up a name other than localhost fails
// with EAI_AGAIN, as libc's resolver connects through internal calls. The build tools that fetch pinned dependencies
// (cargo, rustc, and dart for the Flutter tool, pub and build hooks) are exempt.
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int exempt(void) {
  static int known = -1;
  if (known < 0) {
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    exe[n > 0 ? n : 0] = 0;
    const char *name = strrchr(exe, '/') ? strrchr(exe, '/') + 1 : exe;
    known = !strcmp(name, "cargo") || !strcmp(name, "rustc") || !strcmp(name, "dart");
  }
  return known;
}

static int blocked(const struct sockaddr *to) {
  char host[INET6_ADDRSTRLEN];
  int port, loopback;
  if (!to || exempt()) return 0;
  if (to->sa_family == AF_INET) {
    const struct sockaddr_in *in = (const void *)to;
    port = ntohs(in->sin_port);
    loopback = ntohl(in->sin_addr.s_addr) >> 24 == 127;
    inet_ntop(AF_INET, &in->sin_addr, host, sizeof host);
  } else if (to->sa_family == AF_INET6) {
    const struct sockaddr_in6 *in = (const void *)to;
    port = ntohs(in->sin6_port);
    loopback = IN6_IS_ADDR_LOOPBACK(&in->sin6_addr) ||
               (IN6_IS_ADDR_V4MAPPED(&in->sin6_addr) && in->sin6_addr.s6_addr[12] == 127);
    inet_ntop(AF_INET6, &in->sin6_addr, host, sizeof host);
  } else {
    return 0;
  }
  if (loopback && port != 53) return 0;
  dprintf(2, "offline: blocked %s port %d\n", host, port);
  errno = ENETUNREACH;
  return 1;
}

#define REAL(name) static __typeof__(name) *real; if (!real) real = dlsym(RTLD_NEXT, #name)

int connect(int fd, const struct sockaddr *to, socklen_t length) {
  REAL(connect);
  return blocked(to) ? -1 : real(fd, to, length);
}

ssize_t sendto(int fd, const void *data, size_t size, int flags, const struct sockaddr *to, socklen_t length) {
  REAL(sendto);
  return blocked(to) ? -1 : real(fd, data, size, flags, to, length);
}

ssize_t sendmsg(int fd, const struct msghdr *message, int flags) {
  REAL(sendmsg);
  return blocked(message->msg_name) ? -1 : real(fd, message, flags);
}

int sendmmsg(int fd, struct mmsghdr *messages, unsigned int count, int flags) {
  REAL(sendmmsg);
  for (unsigned int i = 0; i < count; i++) {
    if (blocked(messages[i].msg_hdr.msg_name)) return -1;
  }
  return real(fd, messages, count, flags);
}

int getaddrinfo(const char *name, const char *service, const struct addrinfo *hints, struct addrinfo **result) {
  REAL(getaddrinfo);
  unsigned char address[sizeof(struct in6_addr)];
  size_t length = name ? strlen(name) : 0;
  if (name && !exempt() && strcmp(name, "localhost") && (length < 10 || strcmp(name + length - 10, ".localhost")) &&
      !inet_pton(AF_INET, name, address) && !inet_pton(AF_INET6, name, address)) {
    dprintf(2, "offline: blocked lookup of %s\n", name);
    return EAI_AGAIN;
  }
  return real(name, service, hints, result);
}
