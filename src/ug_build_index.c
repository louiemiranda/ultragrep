// ex: set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include "pcre.h"
#include "request.h"
#include "ug_index.h"
#include "ug_lua.h"
#include "ug_gzip.h"

#define USAGE "Usage: ug_build_index process.lua file\n"

// index file format
// [64bit,64bit] -- timestamp, file offset 
// [32bit, Nbytes] -- extra data

static build_idx_context_t ctx;


void handle_request(request_t *req)
{
    time_t floored_time;
    floored_time = req->time - (req->time % INDEX_EVERY);
    if (!ctx.last_index_time || floored_time > ctx.last_index_time) {
        ug_write_index(ctx.findex, floored_time, req->offset);
        ctx.last_index_time = floored_time;
    }
}

void open_indexes(char *log_fname)
{
    char *index_fname, *gz_index_fname;

    index_fname = ug_get_index_fname(log_fname, "idx");

    if (strcmp(log_fname + (strlen(log_fname) - 3), ".gz") == 0) {
        gz_index_fname = ug_get_index_fname(log_fname, "gzidx");
        /* we don't do incremental index building in gzipped files -- we just truncate and 
         * build over*/
        ctx.findex = fopen(index_fname, "w+");
        ctx.fgzindex = fopen(gz_index_fname, "w+");

        if (!ctx.findex || !ctx.fgzindex) {
            fprintf(stderr, "Couldn't open index files '%s','%s': %s\n", index_fname, gz_index_fname, strerror(errno));
            exit(1);
        }
    } else {
        ctx.findex = fopen(index_fname, "r+");
        if (ctx.findex) {
            /* seek in the log, (and the index, with get_offset_for_timestamp()) to the 
             * last timestamp we indexed */
            fseeko(ctx.flog, ug_get_offset_for_timestamp(ctx.findex, -1), SEEK_SET);
        } else {
            ctx.findex = fopen(index_fname, "w+");
        }
        if (!ctx.findex) {
            fprintf(stderr, "Couldn't open index file '%s': %s\n", index_fname, strerror(errno));
            exit(1);
        }
    }
}

int main(int argc, char **argv)
{
    char *line = NULL, *lua_fname, *log_fname;
    ssize_t line_size;
    size_t allocated;

    if (argc < 3) {
        fprintf(stderr, USAGE);
        exit(1);
    }

    lua_fname = argv[1];
    log_fname = argv[2];

    bzero(&ctx, sizeof(build_idx_context_t));

    ctx.lua = ug_lua_init(lua_fname);

    ctx.flog = fopen(log_fname, "r");
    if (!ctx.flog) {
        perror("Couldn't open log file");
        exit(1);
    }

    open_indexes(log_fname);

    if (strcmp(log_fname + (strlen(log_fname) - 3), ".gz") == 0) {
        build_gz_index(&ctx);
    } else {
        while (1) {
            off_t offset;
            offset = ftello(ctx.flog);
            line_size = getline(&line, &allocated, ctx.flog);

            if ( line_size < 0 )
                break;

            ug_process_line(ctx.lua, line, line_size, offset);
        }
    }
    ug_lua_on_eof(ctx.lua);
    exit(0);
}
