/* <title>GSContext</title>

   <abstract>Generic backend drawing context.</abstract>

   Copyright (C) 2002 Free Software Foundation, Inc.

   Written By: Adam Fedor <fedor@gnu.org>
   Date: Mar 2002
   
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

#ifndef _GSContext_h_INCLUDE
#define _GSContext_h_INCLUDE

#include <Foundation/NSMapTable.h>
#include <AppKit/NSGraphicsContext.h>

@class GSGState;
@class GSDisplayServer;

@interface GSContext : NSGraphicsContext
{
@public
  GSDisplayServer       *server;
  void			*opstack;
  void			*gstack;
  GSGState		*gstate;
  NSMapTable            *gtable;
}

- (GSGState *) currentGState;

@end

/* Error Macros */
#define DPS_WARN(type, resp)		\
    NSDebugLLog(@"GSContext", type, resp)
#define DPS_ERROR(type, resp)		\
    NSLog(type, resp)

/* Current keys used for the info dictionary:
       Key:           Value:
     DisplayName  -- (NSString)name of X server
     ScreenNumber -- (NSNumber)screen number
     DebugContext -- (NSNumber)YES or NO
*/

extern NSString *DPSconfigurationerror;
extern NSString *DPSinvalidaccess;
extern NSString *DPSinvalidcontext;
extern NSString *DPSinvalidexit;
extern NSString *DPSinvalidfileaccess;
extern NSString *DPSinvalidfont;
extern NSString *DPSinvalidid;
extern NSString *DPSinvalidrestore;
extern NSString *DPSinvalidparam;
extern NSString *DPSioerror;
extern NSString *DPSlimitcheck;
extern NSString *DPSnocurrentpoint;
extern NSString *DPSnulloutput;
extern NSString *DPSrangecheck;
extern NSString *DPSstackoverflow;
extern NSString *DPSstackunderflow;
extern NSString *DPStypecheck;
extern NSString *DPSundefined;
extern NSString *DPSundefinedfilename;
extern NSString *DPSundefinedresult;
extern NSString *DPSVMerror;

#endif /* _GSContext_h_INCLUDE */
