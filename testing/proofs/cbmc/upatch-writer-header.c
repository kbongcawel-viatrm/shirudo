// SPDX-License-Identifier: BSD-2-Clause
/*
 * Copyright (c) 2026 Authors of shirudo
 *
 * The header pack_header() of tools/shirudo-build/package.c writes, for
 * every value of every field and every name shorter than its 256 bytes:
 * util/upatch.c's parse_header() takes it from a file of any size and
 * reads back each value, the name padded with zeros as the signed one is.
 */

/* As proof.h, before the system headers can include <ctype.h>. */
#define __NO_CTYPE 1

#include <openssl/evp.h>
#include <linux/bpf.h>
#include <bpf/libbpf.h>

#include "proof.h"
#include "../../../util/string.c"
#include "../../../util/upatch.c"
#include "../../../tools/shirudo-build/package.c"

void harness(void)
{
	__u32 loader_off, loader_len, sig_off, sig_len;
	__u32 data_off, data_len, log_buf_sz, rodata_data_off;
	__u32 type, flags, nr_maps, nr_progs;
	__u8 payload[UPATCH_PAYLOAD_HASH_LEN];
	struct upatch_host_header out;
	char name[UPATCH_NAME_MAX];
	struct upatch_header h;
	size_t len, n, i;

	/*
	 * finalize_object() packs a name its strscpy() fit into 256 bytes,
	 * package_resign_symbols() one upatch_header_name() took from a
	 * header in which it found a NUL.
	 */
	__CPROVER_assume(len < sizeof(name) && !name[len] &&
			 strnlen(name, len) == len);
	__CPROVER_assert(!pack_header(&h, name, type, flags, payload,
				      loader_off, loader_len, sig_off, sig_len,
				      data_off, data_len, log_buf_sz,
				      rodata_data_off, nr_maps, nr_progs),
			 "a name shorter than the field is packed");
	__CPROVER_assume(n >= sizeof(h));
	__CPROVER_assert(!parse_header((const __u8 *)&h, n, &out),
			 "the reader takes the header");
	__CPROVER_assert(out.type == type && out.flags == flags &&
			 out.nr_maps == nr_maps && out.nr_progs == nr_progs &&
			 out.log_buf_sz == log_buf_sz &&
			 out.rodata_data_off == rodata_data_off,
			 "the type, flags, counts, log size and .rodata offset");
	__CPROVER_assert(out.loader_insns_off == loader_off &&
			 out.loader_insns_len == loader_len &&
			 out.signature_off == sig_off &&
			 out.signature_len == sig_len &&
			 out.data_off == data_off && out.data_len == data_len,
			 "the offset and length of every section");
	__CPROVER_assume(i < sizeof(name));
	__CPROVER_assert(out.name[i] == (i < len ? name[i] : '\0'),
			 "the name, padded with zeros");
	__CPROVER_assert(!memcmp(out.payload_sha256, payload, sizeof(payload)),
			 "the payload digest");
}
