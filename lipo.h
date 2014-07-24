/*
 *  lipo.h
 *  Monolingual
 *
 *  Created by Ingmar Stein on 02.02.06.
 *  Copyright 2006-2014 Ingmar Stein. All rights reserved.
 *
 */

#ifndef LIPO_H_INCLUDED
#define LIPO_H_INCLUDED

#include <unistd.h>

int setup_lipo(const char *archs[], unsigned num_archs);
int run_lipo(const char *path, size_t *size_diff);
void finish_lipo(void);

#endif
