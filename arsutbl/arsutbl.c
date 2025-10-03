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
/*																	  */
/*        1) OnDemand will invoke the exit with action == 1           */
/*           so that the exit can create the tablespace (tblsp_name)  */
/*           using (sql)                                              */
/*            *created  -> 0 exit did not create the tablespace,      */
/*                           OnDemand needs to create the tablespace  */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit created the tablespace              */
/*                                                                    */
/*        2) OnDemand will then invoke the exit with action == 2      */
/*           so that the exit can create the table (table_name)       */
/*           inside of the tablespace (tblsp_name) using (sql)        */
/*            *created  -> 0 exit did not create the table,           */
/*                           OnDemand needs to create the table       */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit created the table                   */
/*                                                                    */
/*        3) OnDemand will then invoke the exit with action == 3      */
/*           so that the exit can create the table indexes (idx_name) */
/*           inside of the tablespace (tblsp_name) for table          */
/*           (table_name) using (sql).  This will be invoked based    */
/*           on the number of indexes to create for the appl_grp      */
/*            *created  -> 0 exit did not create the index,           */
/*                           OnDemand needs to create the index       */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit created the index                   */
/*                                                                    */
/*        4) OnDemand will then invoke the exit with action == 4      */
/*           so that the exit can perform any additional work         */
/*            *created  -> Is not used                                */
/*            sql       -> If sql is not an empty string, OnDemand    */
/*                         will issue (sql) to the database           */
/*                                                                    */
/*        If ARS_DB_TABLESPACE_USEREXIT_EXTRA=1 is defined in         */
/*        ars.cfg, then the following actions will also be invoked    */
/*        when OnDemand needs to do further actions:                  */
/*                                                                    */
/*        5) OnDemand will invoke the exit with action == 5           */
/*           so that the exit can drop the tablespace (tblsp_name)    */
/*           using (sql)                                              */
/*            *created  -> 0 exit did not drop the tablespace,        */
/*                           OnDemand needs to drop the tablespace    */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit dropped the tablespace              */
/*                                                                    */
/*        6) OnDemand will invoke the exit with action == 6           */
/*           so that the exit can drop the table (table_name)         */
/*           using (sql) when OnDemand needs to drop a table          */
/*            *created  -> 0 exit did not drop the table,             */
/*                           OnDemand needs to drop the table         */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit dropped the table                   */
/*                                                                    */
/*        7) OnDemand will invoke the exit with action == 7           */
/*           so that the exit can drop the index (idx_name)           */
/*           using (sql)                                              */
/*            *created  -> 0 exit did not drop the index,             */
/*                           OnDemand needs to drop the index         */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit dropped the index                   */
/*                                                                    */
/*        8) OnDemand will invoke the exit with action == 8           */
/*           so that the exit can alter the table (table_name)        */
/*           using (sql)                                              */
/*            *created  -> 0 exit did not alter the table,            */
/*                           OnDemand needs to alter the table        */
/*                           using (sql), which can be left unchanged */
/*                           or modified by the exit                  */
/*            *created  -> 1 exit altered the table                   */
/*********************************************************************/

#include <arscsxit.h>

#include <stdio.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <stdlib.h>


int extractNumber(const char *strIn) {
    while (*strIn && !isdigit((unsigned char)*strIn)) {
        strIn++;  // Skip non-digit characters
    }
    
    // If no digits found, return 0
    if (!*strIn) {
        return 0;
    }

    return atoi(strIn);  // Convert remaining string to integer
}

void strReplace(char *buf, const char *searchStr, const char *replaceStr) {
    char temp[1024];  // temporary buffer; adjust size if needed
    char *pos;

    // Find first occurrence of searchStr
    pos = strstr(buf, searchStr);
    if (!pos) {
        return; // searchStr not found, nothing to replace
    }

    // Copy the part before searchStr into temp
    size_t prefixLen = pos - buf;
    strncpy(temp, buf, prefixLen);
    temp[prefixLen] = '\0';

    // Append replaceStr
    strcat(temp, replaceStr);

    // Append remaining part after searchStr
    strcat(temp, pos + strlen(searchStr));

    // Copy back into original buffer
    strcpy(buf, temp);
}

// Extracts the prefix after the last dot and before first digit
void extractPrefix(const char *strIn, char *prefixOut, size_t size) {
    const char *start = strrchr(strIn, '.');  // Find last dot
    if (start) {
        start++; // Move past the dot
    } else {
        start = strIn; // No dot, start from beginning
    }

    size_t i = 0;
    while (start[i] && !isdigit((unsigned char)start[i]) && i < size - 1) {
        prefixOut[i] = start[i];
        i++;
    }
    prefixOut[i] = '\0'; // Null terminate
}

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

	ArcChar *mytblsp_name = strdup(tblsp_name);
	ArcChar *mytable_name = strdup(table_name);

   rc = 0;
   *created = 0;
/*
	fprintf(stderr,"DEBUG[action.in]: %d\n",action);			
	fprintf(stderr,"DEBUG[tblsp_name.in]: %s\n",tblsp_name);
	fprintf(stderr,"DEBUG[table_name.in]: %s\n",table_name);
	fprintf(stderr,"DEBUG[SQL.in]: %s\n",sql);
*/
	/* get a copy of table name */
	char *agid_name = strdup(table_name);
	memset(agid_name,0,strlen(table_name)+1);

/*
fprintf(stderr,"DEBUG: sizeof=%d\n",strlen(table_name));
*/
	/* extract agid_name from table_name */
	extractPrefix(mytable_name,agid_name,strlen(table_name)+1);

/*
fprintf(stderr,"DEBUG: agid_name=%s\n",agid_name);
*/
	/* extract segid from table_name */
	int segid = extractNumber(mytable_name);
	int tsid = segid - ((segid -1) % 3);

/*
fprintf(stderr,"DEBUG: tsid=%d\n",tsid);
*/

	sprintf(mytblsp_name,"odadm_%s%d",agid_name,tsid);
/*
fprintf(stderr,"DEBUG: newts=%s\n",mytblsp_name);
*/

	if (action == 1) {
		/* create tablespace */
		/* create only when segid id divisible by 3*/
		sprintf(sql,"CALL CHECK_AND_CREATE_TS('%s')",mytblsp_name);
	} else if (action == 2) {
		/* create table */
		
		/* replace the original tblsp_name with tmpts */
		strReplace(sql,tblsp_name,mytblsp_name);
		
	} else if (action == 5) {
		/* drop tablespace */
		*created = 1;  /* don't drop */
		sql[0] = '\0';
	}
	
	strcpy(table_name,mytable_name);
	strcpy(tblsp_name,mytblsp_name);
	
	free(mytable_name);
	free(mytblsp_name);
	free(agid_name);
/*	
	fprintf(stderr,"DEBUG[action.out]: %d\n",action);			
	fprintf(stderr,"DEBUG[tblsp_name.out]: %s\n",tblsp_name);
	fprintf(stderr,"DEBUG[table_name.out]: %s\n",table_name);
	fprintf(stderr,"DEBUG[sql.out]: %s\n",sql);
	fprintf(stderr,"DEBUG[created.out]: %d\n\n",*created);			
*/
   return( rc );
}
