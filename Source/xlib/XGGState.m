/* XGGState - Implements graphic state drawing for Xlib

   Copyright (C) 1998 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@gnu.org>
   Date: Nov 1998
   
   This file is part of the GNU Objective C User Interface Library.

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

#include "config.h"
#include <Foundation/NSObjCRuntime.h>
#include <AppKit/NSBezierPath.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSGraphics.h>
#include "xlib/XGGeometry.h"
#include "xlib/XGContext.h"
#include "xlib/XGGState.h"
#include "xlib/XGContext.h"
#include "xlib/XGPrivate.h"
#include "xlib/xrtools.h"
#include "math.h"

#define XDPY (((RContext *)context)->dpy)

static BOOL shouldDrawAlpha = YES;

#define CHECK_GC \
  if (!xgcntxt) \
    [self createGraphicContext]

#define COPY_GC_ON_CHANGE \
  CHECK_GC; \
  if (sharedGC == YES) \
    [self copyGraphicContext]

#define AINDEX 5

@interface XGGState (Private)
- (void) _alphaBuffer: (gswindow_device_t *)dest_win;
- (void) _paintPath: (ctxt_object_t) drawType;
- (void) createGraphicContext;
- (void) copyGraphicContext;
@end

@implementation XGGState

static	Region	emptyRegion;

+ (void) initialize
{
  static BOOL	beenHere = NO;

  if (beenHere == NO)
    {
      XPoint	pts[5];
      id obj = [[NSUserDefaults standardUserDefaults]
		 stringForKey: @"GraphicCompositing"];
      if (obj)
	shouldDrawAlpha = [obj boolValue];

      beenHere = YES;
      pts[0].x = 0; pts[0].y = 0;
      pts[1].x = 0; pts[1].y = 0;
      pts[2].x = 0; pts[2].y = 0;
      pts[3].x = 0; pts[3].y = 0;
      pts[4].x = 0; pts[4].y = 0;
      emptyRegion = XPolygonRegion(pts, 5, WindingRule);
      NSAssert(XEmptyRegion(emptyRegion), NSInternalInconsistencyException);
    }
}

/* Designated initializer. */
- initWithDrawContext: (GSContext *)drawContext
{
  [super initWithDrawContext: drawContext];

  context = (void *)[(XGContext *)drawContext xrContext];
  NSParameterAssert((RContext *)context);
  draw = 0;
  alpha_buffer = 0;
  color.field[AINDEX] = 1.0;
  xgcntxt = None;
  return self;
}

- (void) dealloc
{
  if ( sharedGC == NO && xgcntxt ) 
    {
      XFreeGC(XDPY, xgcntxt);
    }
  if (clipregion)
    XDestroyRegion(clipregion);
  [super dealloc];
}

- (id) deepen
{
  [super deepen];

  // Copy the GC 
  if (draw != 0)
    [self copyGraphicContext];

  // Copy the clipregion
  if (clipregion)
    {
      Region region = XCreateRegion();

      XIntersectRegion(clipregion, clipregion, region);
      self->clipregion = region;
    }

  return self;
}

- (void) setWindow: (int)number;
{
  gswindow_device_t *gs_win;

  window = number;
  alpha_buffer = 0;
  drawingAlpha = NO;
  gs_win = [XGServer _windowWithTag: window];
  if (gs_win == NULL)
    {
      DPS_ERROR(DPSinvalidid, @"Setting invalid window on gstate");
      return;
    }

  if (gs_win != NULL && gs_win->alpha_buffer != 0)
    {
      alpha_buffer = gs_win->alpha_buffer;
      if (shouldDrawAlpha)
	drawingAlpha = YES;
    }
}

- (void) setDrawable: (Drawable)theDrawable;
{
  draw = theDrawable;
}

- (void) setGraphicContext: (GC)xGraphicContext
{
  GC source;
  unsigned long	mask;
  BOOL old_shared;

  source = xgcntxt;
  old_shared = sharedGC;
  if (xGraphicContext == None)
    return;
  if (xGraphicContext == xgcntxt)
    return;
  
  xgcntxt = xGraphicContext;
  sharedGC = YES;		/* Not sure if we really own the GC */
  /* Update the GC to reflect our settings */
  if (source == None)
    return;
  mask = GCForeground | GCFont | GCFunction | GCFillRule | 
    GCBackground | GCCapStyle | GCJoinStyle | GCLineWidth | 
    GCLineStyle | GCDashOffset | GCDashList;
  XCopyGC(XDPY, source, mask, xgcntxt); 

  if (source != None && old_shared == NO)
    XFreeGC(XDPY, source);
}

/* Set various characteristics of the graphic context */
- (void) setGCValues: (XGCValues)values withMask: (int)mask
{
  COPY_GC_ON_CHANGE;
  if (xgcntxt == 0)
    return;
  XChangeGC(XDPY, xgcntxt, mask, &values);
}

/* Set the GC clipmask.  */
- (void) setClipMask
{
  COPY_GC_ON_CHANGE;
  if (xgcntxt == 0)
    return;
  if (!clipregion)
    {
      XSetClipMask(XDPY, xgcntxt, None);
      return;
    }

  XSetRegion(XDPY, xgcntxt, clipregion);
}

/* Returns the clip region, which must be freed by the caller */
- (Region) xClipRegion
{
  Region region = XCreateRegion();

  if (clipregion)
    XIntersectRegion(clipregion, clipregion, region);
  else 
    XIntersectRegion(emptyRegion, emptyRegion, region);

  return region;
}

- (void) setColor: (xr_device_color_t)acolor;
{
  float alpha = color.field[AINDEX];
  color = acolor;
  color.field[AINDEX] = alpha;
  gcv.foreground = xrColorToPixel((RContext *)context, color);
  [self setGCValues: gcv withMask: GCForeground];
}

- (void) setFont: (NSFont*)newFont
{
  XGFontInfo *font_info;

  if (font == newFont)
    return;

  ASSIGN(font, newFont);

  COPY_GC_ON_CHANGE;
  if (xgcntxt == 0)
    return;

  font_info = (XGFontInfo *)[font fontInfo];
  [font_info setActiveFor: XDPY gc: xgcntxt];
}

- (NSFont*) currentFont
{
  return font;
}

- (void) setOffset: (NSPoint)theOffset
{
  offset = theOffset;
}

- (NSPoint) offset
{
  return offset;
}

- (void) copyGraphicContext
{
  GC source;
  unsigned long	mask;
  
  if (draw == 0)
    {
      DPS_ERROR(DPSinvalidid, @"Copying a GC with no Drawable defined");
      return;
    }

  source = xgcntxt;
  mask = 0xffffffff; /* Copy everything (Hopefully) */
  xgcntxt = XCreateGC(XDPY, draw, 0, NULL);
  XCopyGC(XDPY, source, mask, xgcntxt); 
  sharedGC = NO;
  return;
}

// Create a default graphics context.
- (void) createGraphicContext
{
  if (draw == 0)
    {
      /* This could happen with a defered window */
      DPS_WARN(DPSinvalidid, @"Creating a GC with no Drawable defined");
      return;
    }
  gcv.function = GXcopy;
  gcv.background = ((RContext *)context)->white;
  gcv.foreground = ((RContext *)context)->black;
  gcv.plane_mask = AllPlanes;
  gcv.line_style = LineSolid;
  gcv.fill_style = FillSolid;
  gcv.fill_rule  = WindingRule;
  xgcntxt = XCreateGC(XDPY, draw,
		      GCFunction | GCForeground | GCBackground | GCPlaneMask 
		      | GCFillStyle | GCFillRule| GCLineStyle,
		      &gcv);
  [self setClipMask];
  sharedGC = NO;
  return;
}

- (NSRect)clipRect
{
  XRectangle r;
  r.width = 0; r.height = 0;
  if (clipregion)
    XClipBox(clipregion, &r);
  return NSMakeRect(r.x, r.y, r.width-1, r.height-1);
}

- (BOOL) hasGraphicContext
{
  return (xgcntxt) ? YES : NO;
}

- (BOOL) hasDrawable
{
  return (draw ? YES : NO);
}

- (int) window
{
  return window;
}

- (Drawable) drawable
{
  return draw;
}

- (GC) graphicContext
{
  return xgcntxt;
}

- (void) copyBits: (XGGState*)source fromRect: (NSRect)aRect 
				      toPoint: (NSPoint)aPoint
{
  XRectangle	dst;
  XRectangle    src;
  NSRect	flushRect;
  Drawable	from;

  flushRect.size = aRect.size;
  flushRect.origin = aPoint;

  CHECK_GC;
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for copyBits");
      return;
    }
  from = source->draw;
  if (from == 0)
    {
      DPS_ERROR(DPSinvalidid, @"No source Drawable defined for copyBits");
      return;
    }

  src = XGViewRectToX(source, aRect);
  dst = XGViewRectToX(self, flushRect);
  NSDebugLLog(@"XGGraphics", @"Copy area from %@ to %@",
	      NSStringFromRect(aRect), NSStringFromPoint(aPoint));
  XCopyArea(XDPY, from, draw, xgcntxt,
                src.x, src.y, src.width, src.height, dst.x, dst.y);
}

- (void) _alphaBuffer: (gswindow_device_t *)dest_win
{
  if (dest_win->alpha_buffer == 0 
      && dest_win->type != NSBackingStoreNonretained)    
    {    
      xr_device_color_t old_color;
      dest_win->alpha_buffer = XCreatePixmap(XDPY, draw, 
					     NSWidth(dest_win->xframe),
					     NSHeight(dest_win->xframe), 
					     dest_win->depth);
      
     /* Fill alpha also (opaque by default) */
      old_color = color;
      [self DPSsetgray: 1];
      XFillRectangle(XDPY, dest_win->alpha_buffer, xgcntxt, 0, 0,
		     NSWidth(dest_win->xframe), NSHeight(dest_win->xframe));
      [self setColor: old_color];
    }
  if (shouldDrawAlpha && dest_win->alpha_buffer != 0)
    {
      alpha_buffer = dest_win->alpha_buffer;
      drawingAlpha = YES;
    }
}

- (void) _compositeGState: (XGGState *) source 
                 fromRect: (NSRect) fromRect
                  toPoint: (NSPoint) toPoint
                       op: (NSCompositingOperation) op
                 fraction: (float)delta
{
  XRectangle srect;    
  XRectangle drect;    

  XPoint     toXPoint;  
  
  RXImage *source_im;
  RXImage *source_alpha;

  RXImage *dest_im;
  RXImage *dest_alpha;

  gswindow_device_t *source_win;
  gswindow_device_t *dest_win;

  
  // --- get source information --------------------------------------------------
  NSDebugLLog(@"XGGraphics", @"Composite from %@ to %@",
	      NSStringFromRect(fromRect), NSStringFromPoint(toPoint));

  if (!source)
    source = self;
  
  source_win = [XGServer _windowWithTag: source->window];
  if (!source_win)
    {
      DPS_ERROR(DPSinvalidid, @"Invalid composite source gstate");
      return;
    }

  if (source_win->buffer == 0 && source_win->map_state != IsViewable)
    {
      /* Can't get pixel information from a window that isn't mapped */
      DPS_ERROR(DPSinvalidaccess, @"Invalid gstate buffer");
      return;
    }


  // --- get destination information ----------------------------------------------

  dest_win = [XGServer _windowWithTag: window];
  if (!dest_win)
    {
      DPS_ERROR(DPSinvalidid, @"Invalid composite gstate");
      return;
    }

  if (dest_win->buffer == 0 && dest_win->map_state != IsViewable)
    {
      /* Why bother drawing? */
      return;
    }

     
  // --- determine region to draw --------------------------------------

  {
    NSRect flushRect;                        // destination rectangle
                                             // in View coordinates

    flushRect.size = fromRect.size;
    flushRect.origin = toPoint;
    
    drect = XGViewRectToX(self, flushRect);     

    toXPoint.x = drect.x; 
    toXPoint.y = drect.y; 

    srect = XGViewRectToX (source, fromRect);

    clipXRectsForCopying (source_win, &srect, dest_win, &drect);

    if (XGIsEmptyRect(drect))
      return;

  }

  // --- get destination XImage ----------------------------------------
  
  if (draw == dest_win->ident && dest_win->visibility < 0)
    {
      /* Non-backingstore window isn't visible, so just make up the image */
      dest_im = RCreateXImage((RContext *)context, dest_win->depth, 
			      XGWidth(drect), XGHeight(drect));
    }
  else
    {
      dest_im = RGetXImage((RContext *)context, draw, XGMinX(drect), XGMinY (drect), 
                           XGWidth (drect), XGHeight (drect));
    }

  if (dest_im->image == 0)
    {//FIXME: Should not happen, 
      DPS_ERROR (DPSinvalidaccess, @"unable to fetch destination image");
      return;
    }
  

  // --- get source XImage ---------------------------------------------
    
  source_im = RGetXImage ((RContext *)context, 
                          GET_XDRAWABLE (source_win),
                          XGMinX(srect), XGMinY(srect), 
                          XGWidth(srect), XGHeight(srect));
  
  // --- create alpha XImage -------------------------------------------
  /* Force creation of our alpha buffer */
  [self _alphaBuffer: dest_win];

  /* Composite it */
  source_alpha = RGetXImage((RContext *)context, source_win->alpha_buffer, 
  		    XGMinX(srect), XGMinY(srect), 
  		    XGWidth(srect), XGHeight(srect));

  if (alpha_buffer)
    {
      dest_alpha = RGetXImage((RContext *)context, alpha_buffer,
                              XGMinX(drect), XGMinY(drect), 
                              XGWidth(drect), XGHeight(drect));
    }
  else
    {
      dest_alpha = NULL;
    }

  // --- THE REAL WORK IS DONE HERE! -----------------------------------
  
  {
    XRectangle xdrect = { 0, 0, XGWidth (drect), XGHeight (drect) };
      
    _pixmap_combine_alpha((RContext *)context, source_im, source_alpha, 
                          dest_im, dest_alpha, xdrect,
                          op, [(XGContext *)drawcontext drawMechanism], delta);
  }
  

  // --- put result back in the drawable -------------------------------

  RPutXImage((RContext *)context, draw, xgcntxt, dest_im, 0, 0, 
	     XGMinX(drect), XGMinY(drect), XGWidth(drect), XGHeight(drect));
  
  if (dest_alpha)
    {
      RPutXImage((RContext *)context, dest_win->alpha_buffer, 
		 xgcntxt, dest_alpha, 0, 0, 
		 XGMinX(drect), XGMinY(drect), 
		 XGWidth(drect), XGHeight(drect));
      RDestroyXImage((RContext *)context, dest_alpha);
    }

  // --- clean up ------------------------------------------------------
  
  RDestroyXImage((RContext *)context, dest_im);
  RDestroyXImage((RContext *)context, source_im);
  if (source_alpha)
    RDestroyXImage((RContext *)context, source_alpha);
}

- (void) compositeGState: (GSGState *)source 
                fromRect: (NSRect)aRect
                 toPoint: (NSPoint)aPoint
                      op: (NSCompositingOperation)op
{
  BOOL do_copy, source_alpha;
  XGCValues comp_gcv;

  if (!source)
    source = self;

  /* If we have no drawable, we can't proceed. */
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for composite");
      return;
    }

  /* Check alpha */
#define CHECK_ALPHA						\
  do {								\
    gswindow_device_t *source_win;				\
    source_win = [XGServer _windowWithTag: [(XGGState *)source window]];	\
    source_alpha = (source_win && source_win->alpha_buffer);	\
  } while (0)

  do_copy = NO;
  switch (op)
    {
    case   NSCompositeClear:
      do_copy = YES;
      comp_gcv.function = GXclear;
      break;
    case   NSCompositeCopy:
      do_copy = YES;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeSourceOver:
      CHECK_ALPHA;
      if (source_alpha == NO)
	do_copy = YES;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeSourceIn:
      CHECK_ALPHA;
      if (source_alpha == NO && drawingAlpha == NO)
	do_copy = YES;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeSourceOut:
      do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeSourceAtop:
      CHECK_ALPHA;
      if (source_alpha == NO && drawingAlpha == NO)
	do_copy = YES;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationOver:
      CHECK_ALPHA;
      if (drawingAlpha == NO)
	return;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationIn:
      CHECK_ALPHA;
      if (source_alpha == NO && drawingAlpha == NO)
	return;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationOut:
      do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationAtop:
      CHECK_ALPHA;
      if (source_alpha == NO && drawingAlpha == NO)
	return;
      else
	do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeXOR:
      do_copy = NO;
      comp_gcv.function = GXxor;
      break;
    case   NSCompositePlusDarker:
      do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    case   NSCompositeHighlight:
      do_copy = NO;
      comp_gcv.function = GXxor;
      break;
    case   NSCompositePlusLighter:
      do_copy = NO;
      comp_gcv.function = GXcopy;
      break;
    }

  if (comp_gcv.function != GXcopy)
    [self setGCValues: comp_gcv withMask: GCFunction];

  if (shouldDrawAlpha == NO)
    do_copy = YES;

  if (do_copy)
    {
      [self copyBits: (XGGState *)source fromRect: aRect toPoint: aPoint];
    }
  else
    {
      [self _compositeGState: (XGGState *)source 
            fromRect: aRect
            toPoint: aPoint
            op: op
            fraction: 1];
    }
  

  if (comp_gcv.function != GXcopy)
    {
      comp_gcv.function = GXcopy;
      [self setGCValues: comp_gcv withMask: GCFunction];
    }
}

- (void) dissolveGState: (GSGState *)source
	       fromRect: (NSRect)aRect
		toPoint: (NSPoint)aPoint 
		  delta: (float)delta
{
  /* If we have no drawable, we can't proceed. */
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for dissolve");
      return;
    }

  if (shouldDrawAlpha == NO)
    {
      /* No alpha buffers */
      [self copyBits: (XGGState *)source fromRect: aRect toPoint: aPoint];
    }
  else
    {
      [self _compositeGState: (XGGState *)source 
            fromRect: aRect
            toPoint: aPoint
            op: NSCompositeSourceOver
            fraction: delta];
    }

}

- (void) compositerect: (NSRect)aRect
		    op: (NSCompositingOperation)op
{
  float gray;

  [self DPScurrentgray: &gray];
  if (fabs(gray - 0.667) < 0.005)
    [self DPSsetgray: 0.333];
  else    
    [self DPSsetrgbcolor: 0.121 : 0.121 : 0];

  /* FIXME: Really need alpha dithering to do this right - combine with
     XGBitmapImageRep code? */
  switch (op)
    {
    case   NSCompositeClear:
      gcv.function = GXclear;
      break;
    case   NSCompositeCopy:
      gcv.function = GXcopy;
      break;
    case   NSCompositeSourceOver:
      gcv.function = GXcopy;
      break;
    case   NSCompositeSourceIn:
      gcv.function = GXcopy;
      break;
    case   NSCompositeSourceOut:
      gcv.function = GXcopy;
      break;
    case   NSCompositeSourceAtop:
      gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationOver:
      gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationIn:
      gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationOut:
      gcv.function = GXcopy;
      break;
    case   NSCompositeDestinationAtop:
      gcv.function = GXcopy;
      break;
    case   NSCompositeXOR:
      gcv.function = GXcopy;
      break;
    case   NSCompositePlusDarker:
      gcv.function = GXcopy;
      break;
    case   NSCompositeHighlight:
      gcv.function = GXxor;
      break;
    case   NSCompositePlusLighter:
      gcv.function = GXcopy;
      break;
    default:
      gcv.function = GXcopy;
      break;
    }
  [self setGCValues: gcv withMask: GCFunction];
  [self DPSrectfill: NSMinX(aRect) : NSMinY(aRect) 
	: NSWidth(aRect) : NSHeight(aRect)];

  if (gcv.function != GXcopy)
    {
      gcv.function = GXcopy;
      [self setGCValues: gcv withMask: GCFunction];
    }
  [self DPSsetgray: gray];
}

/* Paint the current path using Xlib calls. All coordinates should already
   have been transformed to device coordinates. */
- (void) _doPath: (XPoint*)pts : (int)count draw: (ctxt_object_t)type
{
  int fill_rule;

  COPY_GC_ON_CHANGE;
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for path");
      return;
    }
  fill_rule = WindingRule;
  switch (type)
    {
    case path_stroke:
      // Hack: Only draw when alpha is not zero
      if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
	XDrawLines(XDPY, draw, xgcntxt, pts, count, CoordModeOrigin);
      if (drawingAlpha)
	{
	  xr_device_color_t old_color;
	  NSAssert(alpha_buffer, NSInternalInconsistencyException);
	  
	  old_color = color;
	  [self DPSsetgray: color.field[AINDEX]];
	  XDrawLines(XDPY, alpha_buffer, xgcntxt, pts, count, CoordModeOrigin);
	  [self setColor: old_color];
	}
      break;
    case path_eofill:
      gcv.fill_rule = EvenOddRule;
      [self setGCValues: gcv withMask: GCFillRule];
      /* NO BREAK */
    case path_fill:
      // Hack: Only draw when alpha is not zero
      if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
	XFillPolygon(XDPY, draw, xgcntxt, pts, count, Complex, 
		     CoordModeOrigin);
      if (drawingAlpha)
	{
	  xr_device_color_t old_color;
	  NSAssert(alpha_buffer, NSInternalInconsistencyException);
	  
	  old_color = color;
	  [self DPSsetgray: color.field[AINDEX]];
	  XFillPolygon(XDPY, alpha_buffer, xgcntxt, pts, count, Complex, 
		       CoordModeOrigin);
	  [self setColor: old_color];
	}
      
      if (gcv.fill_rule == EvenOddRule)
	{
	  gcv.fill_rule = WindingRule;
	  [self setGCValues: gcv withMask: GCFillRule];
	}
      break;
    case path_eoclip:
      fill_rule = EvenOddRule;
      /* NO BREAK */
    case path_clip:
      {
	Region region, new_region;
	region = XPolygonRegion(pts, count, fill_rule);
	if (clipregion)
	  {
	    new_region=XCreateRegion();
	    XIntersectRegion(clipregion, region, new_region);
	    XDestroyRegion(region);
	    XDestroyRegion(clipregion);
	  } else
	    new_region = region;
	clipregion = new_region;
	[self setClipMask];
      }
      break;
    default:
      break;
    }
}

/* fill a complex path. All coordinates should already have been
   transformed to device coordinates. */
- (void) _doComplexPath: (XPoint*)pts 
		       : (int*)types 
		       : (int)count
                     ll: (XPoint)ll 
		     ur: (XPoint)ur 
		   draw: (ctxt_object_t)type
{
  int      x, y, i, j, cnt, nseg = 0;
  XSegment segments[count];
  Window   root_rtn;
  unsigned int width, height, b_rtn, d_rtn;
  
  COPY_GC_ON_CHANGE;
  if (draw == 0)
    {
      DPS_WARN (DPSinvalidid, @"No Drawable defined for path");
      return;
    }

  XGetGeometry (XDPY, draw, &root_rtn, &x, &y, &width, &height,
		&b_rtn, &d_rtn);
  if (ur.x < x  ||  ll.x > x + (int)width)
    {
      return;
    }
  
  if (ll.y < y)
    {
      ll.y = y;
    }
  if (ur.y > y + height)
    {
      ur.y = y + height;
    }
  
  /* draw horizontal lines from the bottom to the top of the path */
  for (y = ll.y; y <= ur.y; y++)
    {
      int    x[count], w[count], y0, y1;
      int    yh = y * 2 + 1;   // shift y of horizontal line
      XPoint lastP, p1;
      
      /* intersect horizontal line with path */
      for (i = 0, cnt = 0; i < count - 1; i++)
	{
	  if (types[i] == 0)    // move (new subpath)
	    {
	      lastP = pts[i];
	    }
	  if (types[i+1] == 0)  // last line of subpath
	    {
	      if (lastP.y == pts[i].y)
		{
		  continue;
		}
	      p1 = lastP;       // close subpath
	    }
	  else
	    {
	      p1 = pts[i+1];
	    }
	  y0 = pts[i].y * 2;
	  y1 = p1.y * 2;
	  if ((y0 < yh  &&  yh < y1) || (y1 < yh  &&  yh < y0) )
	    {
	      int dy = yh - pts[i].y * 2;
	      int ldy = y1 - y0;
	      int ldx = (p1.x - pts[i].x) * 2;
	      
	      x[cnt] = pts[i].x + (ldx * dy / ldy) / 2;
	      /* sum up winding directions */
	      if (type == path_fill)
		{
		  w[cnt] = ((cnt) ? w[cnt-1] : 0) + (y0 < y1) ? -1 : 1;
		}
	      cnt++;
	    }
	}

      /* sort intersections */
      for (i = 0; i < cnt-1; i++)
	{
	  for (j=i+1; j<cnt; j++)
	    {
	      if (x[j] < x[i])
		{
		  x[i] ^= x[j]; 
		  x[j] ^= x[i]; 
		  x[i] ^= x[j];
		}
	    }
	}
      
      /* draw lines between intersections */
      for (i = 0; i < cnt-1; i++)
	{
	  /* eofill -> start line on odd intersection count
	   * winding fill -> start line on odd winding count
	   */
	  if ((type == path_eofill && !(i%2)) || (type == path_fill && w[i]))
	    {
	      segments[nseg].x1 = x[i];
	      segments[nseg].x2 = x[i+1];
	      segments[nseg].y1 = segments[nseg].y2 = y;
	      nseg++;
	    }
	}
      
      // Hack: Only draw when alpha is not zero
      if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
	XDrawSegments (XDPY, draw, xgcntxt, segments, nseg);
      if (drawingAlpha)
	{
	  xr_device_color_t old_color;
	  NSAssert (alpha_buffer, NSInternalInconsistencyException);
	  
	  old_color = color;
	  [self DPSsetgray: color.field[AINDEX]];
	  XDrawSegments (XDPY, alpha_buffer, xgcntxt, segments, nseg);
	  [self setColor: old_color];
	}
      nseg = 0;
    } // for y
}

- (void) _paintPath: (ctxt_object_t) drawType
{
  unsigned	count;
  NSBezierPath *flatPath;
  XPoint       ll, ur;
  
  if (!path)
    {
      return;
    }
  
  ll.x = ll.y = 0x7FFF;
  ur.x = ur.y = 0;
  flatPath = [path bezierPathByFlatteningPath];
  count = [flatPath elementCount];
  if (count)
    {
      XPoint	pts[count];
      int       ts[count];
      unsigned	j, i = 0;
      NSBezierPathElement type;
      NSPoint   points[3];
      BOOL      first = YES;
      NSPoint   p, last_p;
      BOOL doit;
      BOOL complex = NO;
      
      for(j = 0; j < count; j++) 
        {
	  doit = NO;
	  type = [flatPath elementAtIndex: j associatedPoints: points];
	  switch(type) 
	    {
	    case NSMoveToBezierPathElement:
	      if (drawType != path_eofill && drawType != path_fill)
		{
		  if (i > 1)
		    {
		      [self _doPath: pts : i draw: drawType];
		    }
		  i = 0;
		}
	      else if (i > 1)
		{
		  complex = YES;
		}
	      last_p = p = points[0];
	      ts[i] = 0;
	      first = NO;
	      break;
	    case NSLineToBezierPathElement:
	      p = points[0];
	      ts[i] = 1;
	      if (first)
		{
		  last_p = points[0];
		  first = NO;
		}
	      break;
	    case NSCurveToBezierPathElement:
	      // This should not happen, as we flatten the path
	      p = points[2];
	      ts[i] = 1;
	      if (first)
		{
		  last_p = points[2];
		  first = NO;
		}
	      break;
	    case NSClosePathBezierPathElement:
	      p = last_p;
	      ts[i] = 1;
	      doit = YES;
	      break;
	    default:
	      break;
	    }
	  pts[i] = XGWindowPointToX (self, p);
	  if (pts[i].x < ll.x)
	    {
	      ll.x = pts[i].x;
	    }
	  if (pts[i].y > ur.x)
	    {
	      ur.x = pts[i].x;
	    }
	  if (pts[i].y < ll.y)
	    {
	      ll.y = pts[i].y;
	    }
	  if (pts[i].y > ur.y)
	    {
	      ur.y = pts[i].y;
	    }
	  i++;
	  
	  if (doit && i > 1) 
	    {
	      if (complex)
		{
		  [self _doComplexPath: pts  : ts  : i
			ll: ll  ur: ur  draw: drawType];
		}
	      else
		{
		  [self _doPath: pts : i draw: drawType];
		}
	      i = 0;
	    }
	} /* for */

      if (i > 1) 
	{
	  if (complex)
	    {
	      [self _doComplexPath: pts  : ts  : i
		    ll: ll  ur: ur  draw: drawType];
	    }
	  else
	    {
	      [self _doPath: pts : i draw: drawType];
	    }
	}
    }

  /*
   * clip does not delete the current path, so we only clear the path if the
   * operation was not a clipping operation.
   */
  if ((drawType != path_clip) && (drawType != path_eoclip))
    {
      [path removeAllPoints];
    }
}

- (XPoint) viewPointToX: (NSPoint)aPoint
{
  return XGViewPointToX(self, aPoint);
}

- (XRectangle) viewRectToX: (NSRect)aRect
{
  return XGViewRectToX(self, aRect);
}

- (XPoint) windowPointToX: (NSPoint)aPoint
{
  return XGWindowPointToX(self, aPoint);
}

- (XRectangle) windowRectToX: (NSRect)aRect
{
  return XGWindowRectToX(self, aRect);
}

@end

@implementation XGGState (Ops)

- (void) DPScurrentalpha: (float *)alpha
{
  if (alpha)
    *alpha = color.field[AINDEX];
}

- (void)DPScurrentcmykcolor: (float *)c : (float *)m : (float *)y : (float *)k 
{
  xr_device_color_t new = color;
  if (new.space != cmyk_colorspace)
    new = xrConvertToCMYK(new);
  *c = new.field[0];
  *m = new.field[1];
  *y = new.field[2];
  *k = new.field[3];
}

- (void)DPSsetcmykcolor: (float)c : (float)m : (float)y : (float)k 
{
  color.space = cmyk_colorspace;
  color.field[0] = c;
  color.field[1] = m;
  color.field[2] = y;
  color.field[3] = k;
  [self setColor:color];
}

- (void)DPScurrentgray: (float *)gray 
{
  xr_device_color_t gcolor;
  gcolor = xrConvertToGray(color);
  *gray = gcolor.field[0];
}

- (void)DPScurrenthsbcolor: (float *)h : (float *)s : (float *)b 
{
  xr_device_color_t gcolor;
  gcolor = xrConvertToHSB(color);
  *h = gcolor.field[0]; *s = gcolor.field[1]; *b = gcolor.field[2];
}

- (void)DPScurrentrgbcolor: (float *)r : (float *)g : (float *)b 
{
  xr_device_color_t gcolor;
  gcolor = xrConvertToRGB(color);
  *r = gcolor.field[0]; *g = gcolor.field[1]; *b = gcolor.field[2];
}

- (void) DPSsetalpha: (float)a
{
  gswindow_device_t *gs_win;
  color.field[AINDEX] = a;
  gs_win = [XGServer _windowWithTag: window];
  if (!gs_win)
    return;
  if (a < 1.0)
    [self _alphaBuffer: gs_win];
}

- (void)DPSsetgray: (float)gray 
{
  color.space = gray_colorspace;
  color.field[0] = gray;
  [self setColor: color];
}

- (void)DPSsethsbcolor: (float)h : (float)s : (float)b 
{
  color.space = hsb_colorspace;
  color.field[0] = h; color.field[1] = s; color.field[2] = b;
  [self setColor: color];
}

- (void)DPSsetrgbcolor: (float)r : (float)g : (float)b 
{
  color.space = rgb_colorspace;
  color.field[0] = r; color.field[1] = g; color.field[2] = b;
  [self setColor: color];
}

/* ----------------------------------------------------------------------- */
/* Text operations */
/* ----------------------------------------------------------------------- */
typedef enum {
  show_delta, show_array_x, show_array_y, show_array_xy
} show_array_t;

/* Omnibus show string routine that combines that characteristics of
   ashow, awidthshow, widthshow, xshow, xyshow, and yshow */
- (void) _showString: (const char *)s
	    xCharAdj: (float)cx
	    yCharAdj: (float)cy
		char: (char)c
	    adjArray: (const float *)arr
	     arrType: (show_array_t)type
	  isRelative: (BOOL)relative;
{
  int i;
  int len;
  int width;
  NSSize scale;
  XGFontInfo *font_info = [font fontInfo];
  NSPoint point = [path currentPoint];

  if (font_info == nil)
    {
      NSLog(@"DPS (xgps): no font set\n");
      return;
    }

  COPY_GC_ON_CHANGE; 
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for show");
      return;
    }

  /* Use only delta transformations (no offset) */
  len = strlen(s);
  scale = [ctm sizeInMatrixSpace: NSMakeSize(1,1)];
  for (i = 0; i < len; i++)
    {
      NSPoint	delta;
      XPoint	xp;

      // FIXME: We should put this line before the loop
      // and do all computation in display space.
      xp = XGWindowPointToX(self, point);
      width = [font_info widthOf: s+i lenght: 1];
      // Hack: Only draw when alpha is not zero
      if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
	[font_info draw: s+i lenght: 1 
		   onDisplay: XDPY drawable: draw
		   with: xgcntxt at: xp];

      if (drawingAlpha)
	{
	  xr_device_color_t old_color;
	  NSAssert(alpha_buffer, NSInternalInconsistencyException);
	  
	  old_color = color;
	  [self DPSsetgray: color.field[AINDEX]];
	  [font_info draw: s+i lenght: 1 
		     onDisplay: XDPY drawable: alpha_buffer
		     with: xgcntxt at: xp];
	  [self setColor: old_color];
	}
      /* Note we update the current point according to the current 
	 transformation scaling, although the text isn't currently
	 scaled (FIXME). */
      if (type == show_array_xy)
	{
	  delta.x = arr[2*i]; delta.y = arr[2*i+1];
	}
      else if (type == show_array_x)
	{
	  delta.x = arr[i]; delta.y = 0;
	}
      else if (type == show_array_y)
	{
	  delta.x = 0; delta.y = arr[i];
	}
      else
	{
	  delta.x = arr[0]; delta.y = arr[1];
	}
      delta = [ctm deltaPointInMatrixSpace: delta];
      if (relative == YES)
	{
	  delta.x += width * scale.width;
	  delta.y += [font_info ascender] * scale.height;
	}
      if (c && *(s+i) == c)
	{
	  NSPoint cdelta;
	  cdelta.x = cx; cdelta.y = cy;
	  cdelta = [ctm deltaPointInMatrixSpace: cdelta];
	  delta.x += cdelta.x; delta.y += cdelta.y;
	}
      point.x += delta.x;
      if (type != show_delta)
	point.y += delta.y;
    }
  // FIXME: Should we set the current point now?
}

- (void)DPSashow: (float)x : (float)y : (const char *)s 
{
  float arr[2];

  arr[0] = x; arr[1] = y;
  [self _showString: s
    xCharAdj: 0 yCharAdj: 0 char: 0 adjArray: arr arrType: show_delta
    isRelative: YES];
}

- (void)DPSawidthshow: (float)cx : (float)cy : (int)c : (float)ax : (float)ay : (const char *)s 
{
  float arr[2];

  arr[0] = ax; arr[1] = ay;
  [self _showString: s
    xCharAdj: cx yCharAdj: cy char: c adjArray: arr arrType: show_delta
    isRelative: YES];
}

- (void)DPSshow: (const char *)s 
{
  int len;
  int width;
  NSSize scale;
  XPoint xp;
  XGFontInfo *font_info = [font fontInfo];

  if (font_info == nil)
    {
      NSLog(@"DPS (xgps): no font set\n");
      return;
    }

  COPY_GC_ON_CHANGE; 
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for show");
      return;
    }

  len = strlen(s);
  width = [font_info widthOf: s lenght: len];
  xp = XGWindowPointToX(self, [path currentPoint]);
  // Hack: Only draw when alpha is not zero
  if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
    [font_info draw: s lenght: len 
	       onDisplay: XDPY drawable: draw
	       with: xgcntxt at: xp];

  if (drawingAlpha)
    {
      xr_device_color_t old_color;
      NSAssert(alpha_buffer, NSInternalInconsistencyException);

      old_color = color;
      [self DPSsetgray: color.field[AINDEX]];
      [font_info draw: s lenght: len 
		 onDisplay: XDPY drawable: alpha_buffer
		 with: xgcntxt at: xp];

      [self setColor: old_color];
    }
  /* Note we update the current point according to the current 
     transformation scaling, although the text isn't currently
     scaled (FIXME). */
  scale = [ctm sizeInMatrixSpace: NSMakeSize(1, 1)];
  //scale = NSMakeSize(1, 1);
  [path relativeMoveToPoint: NSMakePoint(width * scale.width, 0)];
}

- (void)DPSwidthshow: (float)x : (float)y : (int)c : (const char *)s 
{
  float arr[2];

  arr[0] = 0; arr[1] = 0;
  [self _showString: s
    xCharAdj: x yCharAdj: y char: c adjArray: arr arrType: show_delta
    isRelative: YES];
}

- (void)DPSxshow: (const char *)s : (const float *)numarray : (int)size 
{
  [self _showString: s
    xCharAdj: 0 yCharAdj: 0 char: 0 adjArray: numarray arrType: show_array_x
    isRelative: NO];
}

- (void)DPSxyshow: (const char *)s : (const float *)numarray : (int)size 
{
  [self _showString: s
    xCharAdj: 0 yCharAdj: 0 char: 0 adjArray: numarray arrType: show_array_xy
    isRelative: NO];
}

- (void)DPSyshow: (const char *)s : (const float *)numarray : (int)size 
{
  [self _showString: s
    xCharAdj: 0 yCharAdj: 0 char: 0 adjArray: numarray arrType: show_array_y
    isRelative: NO];
}

/* ----------------------------------------------------------------------- */
/* Gstate operations */
/* ----------------------------------------------------------------------- */
- (void)DPScurrentlinecap: (int *)linecap 
{
  *linecap = gcv.cap_style - CapButt;
}

- (void)DPScurrentlinejoin: (int *)linejoin 
{
  *linejoin = gcv.join_style - JoinMiter;
}

- (void)DPScurrentlinewidth: (float *)width 
{
  *width = gcv.line_width;
}

- (void)DPSinitgraphics 
{
  [ctm makeIdentityMatrix];
  DESTROY(path);
  if (clipregion)
    XDestroyRegion(clipregion);
  clipregion = 0;
  /* FIXME: reset the GC */
  color.space = gray_colorspace; 
  color.field[0] = 0.0;
  [self setColor: color];
  color.field[AINDEX] = 1.0;
}

- (void)DPSsetdash: (const float *)pat : (int)size : (float)pat_offset 
{
  int dash_offset;
  char dash_list[size];
  int i;

  gcv.line_style = LineOnOffDash;
  [self setGCValues: gcv withMask: GCLineStyle];

  // FIXME: How to convert those values?
  dash_offset = (int)pat_offset;
  for (i = 0; i < size; i++)
    dash_list[i] = (char)pat[i];

  // We can only set the dash pattern, if xgcntxt exists.
  if (xgcntxt == 0)
    return;
  XSetDashes(XDPY, xgcntxt, dash_offset, dash_list, size);
}

- (void)DPSsetlinecap: (int)linecap 
{
  gcv.cap_style = linecap + CapButt;
  [self setGCValues: gcv withMask: GCCapStyle];
}

- (void)DPSsetlinejoin: (int)linejoin 
{
  gcv.join_style = linejoin + JoinMiter;
  [self setGCValues: gcv withMask: GCJoinStyle];
}

- (void)DPSsetlinewidth: (float)width 
{
  int	w;

  /*
   * Evil hack to get drawing to work - with a line thickness of 1, the
   * rectangles we draw seem to lose their bottom right corners irrespective
   * of the join/cap settings - but with a thickness of zero things work.
   */
  if (width < 1.5)
    width = 0.0;

  w = (int)width;
  if (gcv.line_width != w)
    {
      gcv.line_width = w;
      [self setGCValues: gcv withMask: GCLineWidth];
    }
}

- (void) DPSsetmiterlimit: (float)limit
{
  /* Do nothing. X11 does its own thing and doesn't give us a choice */
}

/* ----------------------------------------------------------------------- */
/* Paint operations */
/* ----------------------------------------------------------------------- */
- (void)DPSclip 
{
  [self _paintPath: path_clip];
}

- (void)DPSeoclip 
{
  [self _paintPath: path_eoclip];
}

- (void)DPSeofill 
{
  [self _paintPath: path_eofill];
}

- (void)DPSfill 
{
  [self _paintPath: path_fill];
}

- (void)DPSinitclip 
{
  if (clipregion)
    XDestroyRegion(clipregion);
  clipregion = 0;
  [self setClipMask];
}

- (void)DPSrectclip: (float)x : (float)y : (float)w : (float)h 
{
  XRectangle    xrect;

  CHECK_GC;

  xrect = XGViewRectToX(self, NSMakeRect(x, y, w, h));

  if (clipregion == 0)
    {
      clipregion = XCreateRegion();
      XUnionRectWithRegion(&xrect, clipregion, clipregion);
    }
  else
    {
      Region region;
      region = XCreateRegion();
      XUnionRectWithRegion(&xrect, region, region);
      XIntersectRegion(clipregion, region, clipregion);
      XDestroyRegion(region);
    }
  [self setClipMask];
}

- (void)DPSrectfill: (float)x : (float)y : (float)w : (float)h 
{
  XRectangle	bounds;
  
  CHECK_GC;
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for drawing");
      return;
    }

  bounds = XGViewRectToX(self, NSMakeRect(x, y, w, h));
  // Hack: Only draw when alpha is not zero
  if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
    XFillRectangle(XDPY, draw, xgcntxt,
		   bounds.x, bounds.y, bounds.width, bounds.height);

  if (drawingAlpha)
    {
      /* Fill alpha also */
      xr_device_color_t old_color;
      NSAssert(alpha_buffer, NSInternalInconsistencyException);
      
      old_color = color;
      [self DPSsetgray: color.field[AINDEX]];
      XFillRectangle(XDPY, alpha_buffer, xgcntxt,
		 bounds.x, bounds.y, bounds.width, bounds.height);
      [self setColor: old_color];
    }
}

- (void)DPSrectstroke: (float)x : (float)y : (float)w : (float)h 
{
  XRectangle	bounds;
  
  CHECK_GC;
  if (draw == 0)
    {
      DPS_WARN(DPSinvalidid, @"No Drawable defined for drawing");
      return;
    }

  bounds = XGViewRectToX(self, NSMakeRect(x, y, w, h));
  if (bounds.width > 0)
    bounds.width--;
  if (bounds.height > 0)
    bounds.height--;
  // Hack: Only draw when alpha is not zero
  if (drawingAlpha == NO || color.field[AINDEX] != 0.0)
    XDrawRectangle(XDPY, draw, xgcntxt,
		   bounds.x, bounds.y, bounds.width, bounds.height);

  if (drawingAlpha)
    {
      /* Fill alpha also */
      xr_device_color_t old_color;
      NSAssert(alpha_buffer, NSInternalInconsistencyException);

      old_color = color;
      [self DPSsetgray: color.field[AINDEX]];
      XDrawRectangle(XDPY, alpha_buffer, xgcntxt,
		 bounds.x, bounds.y, bounds.width, bounds.height);
      [self setColor: old_color];
    }
}

- (void)DPSstroke 
{
  [self _paintPath: path_stroke];
}

/* ----------------------------------------------------------------------- */
/* NSGraphics Ops */
/* ----------------------------------------------------------------------- */
- (void)DPSimage: (NSAffineTransform*) matrix : (int) pixelsWide : (int) pixelsHigh
		: (int) bitsPerSample : (int) samplesPerPixel 
		: (int) bitsPerPixel : (int) bytesPerRow : (BOOL) isPlanar
		: (BOOL) hasAlpha : (NSString *) colorSpaceName
		: (const unsigned char *const [5]) data
{
  BOOL one_is_black, fast_min;
  NSRect rect;
  XRectangle sr, dr, cr;
  RXImage *dest_im, *dest_alpha;
  gswindow_device_t *dest_win;
  int cspace;
  NSAffineTransform *old_ctm = nil;

  // FIXME for now we hard code the minification behaviour
  fast_min = YES;

  rect = NSZeroRect;
  one_is_black = NO;
  cspace = rgb_colorspace;
  rect.size.width = (float) pixelsWide;
  rect.size.height = (float) pixelsHigh;

  // default is 8 bit grayscale 
  if (!bitsPerSample)
    bitsPerSample = 8;
  if (!samplesPerPixel)
    samplesPerPixel = 1;

  // FIXME - does this work if we are passed a planar image but no hints ?
  if (!bitsPerPixel)
    bitsPerPixel = bitsPerSample * samplesPerPixel;
  if (!bytesPerRow)
    bytesPerRow = (bitsPerPixel * pixelsWide) / 8;

  /* make sure its sane - also handles row padding if hint missing */
  while((bytesPerRow * 8) < (bitsPerPixel * pixelsWide))
    bytesPerRow++;

  /* get the colour space */
  if (colorSpaceName)
    {
      if ([colorSpaceName isEqualToString: NSDeviceRGBColorSpace])
	cspace = rgb_colorspace;
      else if([colorSpaceName isEqualToString: NSDeviceCMYKColorSpace])
	cspace = cmyk_colorspace;
      else if([colorSpaceName isEqualToString: NSDeviceWhiteColorSpace])
	cspace = gray_colorspace;
      else if([colorSpaceName isEqualToString: NSDeviceBlackColorSpace]) 
        {
	  cspace = gray_colorspace;
	  one_is_black = YES;
	} 
      else 
        {
	  // if we dont recognise the name use RGB or greyscale as appropriate
	  NSLog(@"XGContext (DPSImage): Unknown colour space %@", colorSpaceName);
	  if(samplesPerPixel > 2)
	    cspace = rgb_colorspace;
	  else
	    cspace = gray_colorspace;
	}
    }

  // Apply the additional transformation
  if (matrix)
    {
      old_ctm = [ctm copy];
      [ctm appendTransform: matrix];
    }

  // --- Get our drawable info -----------------------------------------
  dest_win = [XGServer _windowWithTag: window];
  if (!dest_win)
    {
      DPS_ERROR(DPSinvalidid, @"Invalid image gstate");
      return;
    }
  

  // --- Determine screen coverage --------------------------------------
  if (viewIsFlipped)
    rect.origin.y -= rect.size.height;
  sr = [self viewRectToX: rect];

  // --- Determine region to draw --------------------------------------
  if (clipregion)
    XClipBox (clipregion, &cr);
  else
    cr = sr;

  dr = XGIntersectionRect (sr, cr);


  // --- If there is nothing to draw return ----------------------------
  if (XGIsEmptyRect (dr))
    {
      if (old_ctm != nil)
	{
	  RELEASE(ctm);
	  // old_ctm is already retained
	  ctm = old_ctm;
	}
      return;
    }
  
  if (dest_win->buffer == 0 && dest_win->map_state != IsViewable)
    {
      if (old_ctm != nil)
	{
	  RELEASE(ctm);
	  // old_ctm is already retained
	  ctm = old_ctm;
	}
      return;
    }


  // --- Get the destination images ------------------------------------
  dest_im = RGetXImage ((RContext *)context, draw, XGMinX (dr), XGMinY (dr),
                        XGWidth (dr), XGHeight (dr));
  
  // Force creation of our alpha buffer
  if (hasAlpha)
    {
      [self _alphaBuffer: dest_win];
    }

  // Composite it
  if (alpha_buffer != 0)
    {
      dest_alpha = RGetXImage ((RContext *)context, alpha_buffer,
                               XGMinX (dr), XGMinY (dr),
                               XGWidth (dr), XGHeight (dr));
    }
  else
    {
      dest_alpha = 0;
    }
  

  if (hasAlpha && alpha_buffer && 
      (dest_alpha == 0 || dest_alpha->image == 0))
    {
      NSLog(@"XGContext (DPSimage): Cannot create alpha image\n");
      if (old_ctm != nil)
        {
	  RELEASE(ctm);
	  // old_ctm is already retained
	  ctm = old_ctm;
	}
      return;
    }

  // --- The real work is done HERE ------------------------------------
  _bitmap_combine_alpha((RContext *)context, (unsigned char **)data,
			pixelsWide, pixelsHigh,
			bitsPerSample, samplesPerPixel,
			bitsPerPixel, bytesPerRow,
			cspace, one_is_black,
			isPlanar, hasAlpha, fast_min,
			dest_im, dest_alpha, sr, dr,
			0, [(XGContext *)drawcontext drawMechanism]);

  /* Draw into the window/buffer */
  RPutXImage((RContext *)context, draw, xgcntxt, dest_im, 0, 0, 
	     XGMinX (dr), XGMinY (dr), XGWidth (dr), XGHeight (dr));
  if (dest_alpha)
    {
      RPutXImage((RContext *)context, dest_win->alpha_buffer, 
		 xgcntxt, dest_alpha, 0, 0,
                 XGMinX (dr), XGMinY (dr), XGWidth (dr), XGHeight (dr));

      RDestroyXImage((RContext *)context, dest_alpha);
    }
  RDestroyXImage((RContext *)context, dest_im);

  if (old_ctm != nil)
    {
      RELEASE(ctm);
      // old_ctm is already retained
      ctm = old_ctm;
    }
}

@end

