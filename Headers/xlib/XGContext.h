/* <title>XGContext</title>

   <abstract>Backend drawing context using the Xlib library.</abstract>

   Copyright (C) 1995 Free Software Foundation, Inc.

   Written By: Adam Fedor <fedor@gnu.org>
   Date: Nov 1998
   
   This file is part of the GNU Objective C User Interface library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
   */

#ifndef _XGContext_h_INCLUDE
#define _XGContext_h_INCLUDE

#include "gsc/GSContext.h"
#include "x11/XGServer.h"
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

@interface XGContext : GSContext
{
  XGDrawMechanism	drawMechanism;
}

- (XGDrawMechanism) drawMechanism;
- (Display*) xDisplay;
- (void *) xrContext;

@end

#endif /* _XGContext_h_INCLUDE */