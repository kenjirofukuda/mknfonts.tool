/*
copyright 2002 Alexander Malmberg <alexander@malmberg.org>
*/

#include <Foundation/NSString.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSFileManager.h>

#include <ft2build.h>
#include FT_FREETYPE_H


static FT_Library ftlib;


/*
from GNUstep's core/back/Source/art/ftfont.m
GNU LGPL:ed
*/
#define NSBoldFontMask 0
#define NSItalicFontMask 0
#define NSCondensedFontMask 0
static int traits_from_string(NSString *s, unsigned int *traits, unsigned int *weight)
{
static struct
{
  NSString *str;
  unsigned int trait;
  int weight;
} suffix[] = {
/* TODO */
{@"Ultralight"     ,0                         , 1},
{@"Thin"           ,0                         , 2},
{@"Light"          ,0                         , 3},
{@"Extralight"     ,0                         , 3},
{@"Book"           ,0                         , 4},
{@"Regular"        ,0                         , 5},
{@"Plain"          ,0                         , 5},
{@"Display"        ,0                         , 5},
{@"Roman"          ,0                         , 5},
{@"Semilight"      ,0                         , 5},
{@"Medium"         ,0                         , 6},
{@"Demi"           ,0                         , 7},
{@"Demibold"       ,0                         , 7},
{@"Semi"           ,0                         , 8},
{@"Semibold"       ,0                         , 8},
{@"Bold"           ,NSBoldFontMask            , 9},
{@"Extra"          ,NSBoldFontMask            ,10},
{@"Extrabold"      ,NSBoldFontMask            ,10},
{@"Heavy"          ,NSBoldFontMask            ,11},
{@"Heavyface"      ,NSBoldFontMask            ,11},
{@"Ultrabold"      ,NSBoldFontMask            ,12},
{@"Black"          ,NSBoldFontMask            ,12},
{@"Ultra"          ,NSBoldFontMask            ,13},
{@"Ultrablack"     ,NSBoldFontMask            ,13},
{@"Fat"            ,NSBoldFontMask            ,13},
{@"Extrablack"     ,NSBoldFontMask            ,14},
{@"Obese"          ,NSBoldFontMask            ,14},
{@"Nord"           ,NSBoldFontMask            ,14},

{@"Italic"         ,NSItalicFontMask          ,-1},
{@"Oblique"        ,NSItalicFontMask          ,-1},

{@"Cond"           ,NSCondensedFontMask       ,-1},
{@"Condensed"      ,NSCondensedFontMask       ,-1},
{nil,0,-1}
};
  int i;

  *traits = 0;
//  printf("do '%@'\n", s);
  while ([s length] > 0)
    {
//      printf("  got '%@'\n", s);
      if ([s hasSuffix: @"-"] || [s hasSuffix: @" "])
	{
//	  printf("  do -\n");
	  s = [s substringToIndex: [s length] - 1];
	  continue;
	}
      for (i = 0; suffix[i].str; i++)
	{
	  if (![s hasSuffix: suffix[i].str])
	    continue;
//	  printf("  found '%@'\n", suffix[i].str);
	  if (suffix[i].weight != -1)
	    *weight = suffix[i].weight;
	  (*traits) |= suffix[i].trait;
	  s = [s substringToIndex: [s length] - [suffix[i].str length]];
	  break;
	}
      if (!suffix[i].str)
	break;
    }
//  printf("end up with '%@'\n", s);
  return [s length];
}



@interface FaceInfo : NSObject
{
@public
	NSString *postScriptName;
	NSString *familyName;
	NSString *faceName;

	NSMutableArray *files;
}
-(BOOL) collectFaceInfo;
-(NSDictionary *) faceInfoDictionary;
@end

@implementation FaceInfo
- init
{
	self=[super init];
	files=[[NSMutableArray alloc] init];
	return self;
}

-(void) dealloc
{
	DESTROY(files);
	[super dealloc];
}

-(NSString *) description
{
	return [NSString stringWithFormat: @"<FaceInfo: psname='%@' family='%@' face='%@' files=%@>",
		postScriptName,familyName,faceName,files];
}


-(BOOL) collectFaceInfo
{
	FT_Face face;
	int i;
	const char *psname;
	unsigned int foo,bar;

	for (i=1;i<[files count];i++)
	{
		NSString *f;
		f=[files objectAtIndex: i];
		if ([[f pathExtension] isEqualToString: @"pfa"] ||
			 [[f pathExtension] isEqualToString: @"pfb"])
		{
			[f retain];
			[files removeObject: f];
			[files insertObject: f atIndex: 0];
			[f release];
		}
	}

	if (FT_New_Face(ftlib,[[files objectAtIndex: 0] cString],0,&face))
	{
		GSPrintf(stderr,@"unable to open %@, ignoring\n",[files objectAtIndex: 0]);
		return NO;
	}
	for (i=1;i<[files count];i++)
	{
		if (FT_Attach_File(face,[[files objectAtIndex: i] cString]))
		{
			GSPrintf(stderr,@"warning: unable to attach %@\n",[files objectAtIndex: i]);
		}
	}

	psname=FT_Get_Postscript_Name(face);
	if (!psname)
	{
		GSPrintf(stderr,@"couldn't get postscript name for %@, ignoring\n",[files objectAtIndex: 0]);
		return NO;
	}
	postScriptName=[[NSString alloc] initWithCString: psname];

	familyName=[[NSString alloc] initWithCString: face->family_name];
	faceName=[[NSString alloc] initWithCString: face->style_name];

	if (traits_from_string(faceName,&foo,&bar))
	{
		GSPrintf(stderr,@"warning: couldn't fully parse '%@' (%@)\n",faceName,postScriptName);
	}

	FT_Done_Face(face);

	return YES;
}

-(NSDictionary *) faceInfoDictionary
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		files,@"Files",
		postScriptName,@"PostScriptName",
		faceName,@"Name",
		nil];
}

@end


static NSArray *group_files(NSArray *files)
{
	NSSet *combine_set=[NSSet setWithObjects: @"pfa",@"pfb",@"afm",@"pfm",nil];
	NSMutableDictionary *groups;
	NSArray *a;
	int i;

	groups=[[NSMutableDictionary alloc] init];
	for (i=0;i<[files count];i++)
	{
		NSString *f=[files objectAtIndex: i];
		NSString *key;
		FaceInfo *fa;

		if ([combine_set containsObject: [f pathExtension]])
			key=[f stringByDeletingPathExtension];
		else
			key=f;

		fa=[groups objectForKey: key];
		if (!fa)
		{
			fa=[[[FaceInfo alloc] init] autorelease];
			[groups setObject: fa  forKey: key];
		}
		[fa->files addObject: f];
	}

	a=[groups allValues];
	DESTROY(groups);
	return a;
}


int main(int argc, char **argv)
{
	CREATE_AUTORELEASE_POOL(arp);

	NSMutableArray *files;
	NSArray *groups;
	int i;

	NSMutableDictionary *families;


	files=[[NSMutableArray alloc] init];
	for (i=1;i<argc;i++)
	{
		[files addObject: [NSString stringWithCString: argv[i]]];
	}

	groups=[group_files(files) retain];
	DESTROY(files);

	if (FT_Init_FreeType(&ftlib))
	{
		fprintf(stderr,"failed to initialize freetype\n");
		return 1;
	}

	families=[[NSMutableDictionary alloc] init];
	for (i=0;i<[groups count];i++)
	{
		NSMutableArray *ma;
		FaceInfo *fi=[groups objectAtIndex: i];
		if ([fi collectFaceInfo])
		{
			ma=[families objectForKey: fi->familyName];
			if (!ma)
			{
				ma=[[[NSMutableArray alloc] init] autorelease];
				[families setObject: ma forKey: fi->familyName];
			}
			[ma addObject: fi];
		}
	}
	DESTROY(groups);

	{
		NSFileManager *fm=[NSFileManager defaultManager];
		NSEnumerator *e;
		NSString *family;
		int i,c;

		NSMutableDictionary *family_info;
		NSMutableArray *faces;
		NSArray *faceinfos;
		FaceInfo *fi;
		NSString *path;


		e=[families keyEnumerator];
		while ((family=[e nextObject]))
		{
			family_info=[[NSMutableDictionary alloc] init];
			faces=[[NSMutableArray alloc] init];
			[family_info setObject: faces  forKey: @"Faces"];

			path=[family stringByAppendingPathExtension: @"nfont"];

			[fm createDirectoryAtPath: path
				attributes: nil];

			faceinfos=[families objectForKey: family];
			for (c=[faceinfos count],i=0;i<c;i++)
			{
				fi=[faceinfos objectAtIndex: i];
				[faces addObject: [fi faceInfoDictionary]];
			}

			[family_info
				writeToFile: [path stringByAppendingPathComponent: @"FontInfo.plist"]
				atomically: NO];
			DESTROY(faces);
			DESTROY(family_info);
		}
	}
	DESTROY(families);

	DESTROY(arp);
	return 0;
}

