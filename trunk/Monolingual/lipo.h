/*
 *  lipo.h
 *  Monolingual
 *
 *  Created by Ingmar Stein on 02.02.06.
 *  Copyright 2006 Ingmar Stein. All rights reserved.
 *
 */

#ifndef LIPO_H_INCLUDED
#define LIPO_H_INCLUDED

#include <unistd.h>

int run_lipo(const char *path, const char *archs[], unsigned num_archs, off_t *size_diff);

#endif
