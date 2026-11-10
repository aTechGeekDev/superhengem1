/* Linux/arm64 stand-ins for the Darwin APIs the engine's core and tests use (scratch build only). */
#pragma once
#define _GNU_SOURCE
#include <stdint.h>
#include <time.h>
#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <errno.h>
typedef unsigned int mach_port_t; typedef int kern_return_t; typedef unsigned int mach_msg_type_number_t;
typedef int *thread_info_t; typedef struct { int seconds, microseconds; } time_value_t;
typedef struct { time_value_t user_time, system_time; int run_state; } thread_basic_info_data_t;
typedef uintptr_t vm_address_t; typedef int vm_prot_t;
#define TH_STATE_RUNNING 1
#define THREAD_BASIC_INFO 3
#define THREAD_BASIC_INFO_COUNT 10
#define KERN_SUCCESS 0
#define VM_FLAGS_ANYWHERE 1
#define VM_INHERIT_NONE 2
#define MAP_JIT 0
#define FALSE 0
static inline uint64_t mach_absolute_time(void) { /* 24 MHz ticks, as on Apple silicon */
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 24000000ull + (uint64_t)ts.tv_nsec * 24 / 1000; }
typedef struct { uint32_t numer, denom; } mach_timebase_info_data_t;
static inline int mach_timebase_info(mach_timebase_info_data_t *t) { t->numer = 125; t->denom = 3; return 0; }
static inline mach_port_t mach_thread_self(void) { return 1; }
static inline mach_port_t mach_task_self(void) { return 1; }
static inline kern_return_t thread_info(mach_port_t a, int b, thread_info_t c, mach_msg_type_number_t *d) { (void)a;(void)b;(void)c;(void)d; return -1; }
static inline kern_return_t mach_port_deallocate(mach_port_t a, mach_port_t b) { (void)a;(void)b; return 0; }
static inline kern_return_t vm_remap(int t, vm_address_t *to, size_t n, int m, int f, int s, vm_address_t from, int c, vm_prot_t *cur, vm_prot_t *max, int inh) {
    (void)t;(void)to;(void)n;(void)m;(void)f;(void)s;(void)from;(void)c;(void)cur;(void)max;(void)inh; return -1; }
static inline void pthread_jit_write_protect_np(int on) { (void)on; }
static inline void sys_icache_invalidate(void *p, size_t n) { __builtin___clear_cache((char *)p, (char *)p + n); }
static inline int pthread_cond_timedwait_relative_np(pthread_cond_t *c, pthread_mutex_t *m, const struct timespec *rel) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += rel->tv_sec; ts.tv_nsec += rel->tv_nsec; if (ts.tv_nsec >= 1000000000) ts.tv_sec++, ts.tv_nsec -= 1000000000;
    return pthread_cond_timedwait(c, m, &ts); }
