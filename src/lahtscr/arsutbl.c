#define _ARSUSTBL_C

/*********************************************************************/
/*                                                                   */
/* MODULE NAME: ARSUSTBL.C                                            */
/*                                                                   */
/*                                                                   */
/* SYNOPSIS:  OnDemand TableSpace Creation Exit                      */
/*                                                                   */
/*                                                                   */
/* DESCRIPTION:  This module contains the Table Space creation       */
/*               function.                                           */
/*                                                                   */
/* COPYRIGHT:                                                        */
/*  5724-J33 (C) COPYRIGHT IBM CORPORATION 2007.                     */
/*  All Rights Reserved                                              */
/*  Licensed Materials - Property of IBM                             */
/*                                                                   */
/*  US Government Users Restricted Rights - Use, duplication or      */
/*  disclosure restricted by GSA ADP Schedule Contract with IBM Corp.*/
/*                                                                   */
/* NOTE: This program sample is provided on an as-is basis.          */
/*       The licensee of the OnDemand product is free to copy,       */
/*       revise modify, and make derivative works of this program    */
/*       sample as they see fit.                                     */
/*                                                                   */
/*********************************************************************/

#include <arscsxit.h>
#include <string.h>
#include <stdio.h>

ArcI32
ARSCSXIT_EXPORT
ARSCSXIT_API
TBLSPCRT( ArcCSXitApplGroup *appl_grp,
          ArcChar *tblsp_name,
          ArcChar *table_name,
          ArcChar *idx_name,
          ArcChar *sql,
          ArcI32 action,
          ArcI32 *created,
          ArcChar *instance
        )
{
   ArcI32 rc;

   rc = 0;
   *created = 0;
	if (action == 1) {
//		fprintf(stderr,"BEFOR: %s\n",sql);
		strcpy(sql,"call lahtscr('");
		strcat(sql,tblsp_name);
		strcat(sql,"')");
//		fprintf(stderr,"AFTER: %s\n",sql);
	}
   return( rc );
}
