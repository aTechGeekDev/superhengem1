#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/futex.h>
/* Darwin's __ulock_* on Linux futexes (the 32-bit word at addr; ack_seq is little-endian, low half first). */
int __ulock_wait(uint32_t op, void *addr, uint64_t value, uint32_t timeout_us) {
    (void)op;
    struct timespec ts = {timeout_us / 1000000, (long)(timeout_us % 1000000) * 1000};
    return (int)syscall(SYS_futex, addr, FUTEX_WAIT, (uint32_t)value, timeout_us ? &ts : NULL, NULL, 0);
}
int __ulock_wake(uint32_t op, void *addr, uint64_t v) {
    (void)v;
    return (int)syscall(SYS_futex, addr, FUTEX_WAKE, (op & 0x100) ? 0x7fffffff : 1, NULL, NULL, 0);
}
