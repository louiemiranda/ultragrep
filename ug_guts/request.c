#include <stdio.h>
#include <stdlib.h>
#include "request.h"

request_t* alloc_request() {
    request_t* r = (request_t*)malloc(sizeof(request_t));
    r->lines = 0;
    r->buf = NULL;
    r->session = NULL;
    r->next = NULL;
    r->prev = NULL;
    r->time = 0;
    return(r);
}

void free_request(request_t* r) {
    int i=0;

    for(i = 0; i < r->lines; i++) {
        free(r->buf[i]);
    }
    if(r->buf) {
        free(r->buf);
    }
    if(r->session) {
        free(r->session);
    }
    r->lines = 0;
    r->buf = NULL;
    free(r);
}

void add_to_request(request_t* req, char* line) {
    req->buf = realloc(req->buf, sizeof(char*) * (req->lines + 1));
    req->buf[req->lines] = line;
    req->lines++;
}
