#include "xmlparser.h"
#include <stdlib.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xpath.h>

#define TAG __FILE__
#define MAX_TAG 20
#define MAX_TAG_LENGTH 50
#define THIS_FILE "xmlparser.c"

xmlDocPtr getdoc(char *docname)
{
	xmlDocPtr doc;

	doc = xmlParseFile(docname);
	if (doc == NULL) {
		printf("Document not parsed successfully");
		return NULL;
	}

	return doc;
}

xmlXPathObjectPtr getnodeset(xmlDocPtr doc, xmlChar * xpath)
{

	xmlXPathContextPtr context;
	xmlXPathObjectPtr result;

	context = xmlXPathNewContext(doc);
	if (context == NULL) {
		printf("Error in xmlXPathNewContext\n");
		return NULL;
	}

	result = xmlXPathEvalExpression(xpath, context);
	xmlXPathFreeContext(context);
	if (result == NULL) {
		printf("Error in xmlXPathEvalExpression\n");
		return NULL;
	}

	if (xmlXPathNodeSetIsEmpty(result->nodesetval)) {
		xmlXPathFreeObject(result);
		printf("No result\n");
		return NULL;
	}

	return result;
}

static void die(char *msg)
{
	printf("%s", msg);
	return;
}

/*
 * Get element content
 *
 *@cur: root node
 *@childNode: child node name
 *
 *return: content of an node in xmlChar pointer
 * */
static xmlChar *parseNode(xmlDocPtr doc, xmlNodePtr cur, char *childNode)
{
	xmlChar *key;

	cur = cur->xmlChildrenNode;

	while (cur != NULL) {
		if ((!xmlStrcmp(cur->name, (const xmlChar *)childNode))) {
			key = xmlNodeListGetString(doc, cur->xmlChildrenNode, 1);

			printf("%s\n", key);
		}

		cur = cur->next;
	}

	return key;
}

char **parseDoc(char *docString, char *rootNode, char *childNode)
{
	xmlDocPtr doc;
	xmlNodePtr cur;
	int i = 0;
	char **result;
	int j;

	result = (char **)malloc(MAX_TAG * sizeof(char *));

	for (j = 0; j < MAX_TAG; j++) {
		result[j] = (char *)malloc(MAX_TAG_LENGTH * sizeof(char));
		memset(result[j], 0, MAX_TAG_LENGTH);
	}

	doc = xmlParseDoc(docString);

	if (doc == NULL) {
		die("doc null\n");
		return NULL;
	}

	cur = xmlDocGetRootElement(doc);

	if (cur == NULL) {
		xmlFreeDoc(doc);
		die("node null\n");
		return NULL;
	}
	//while(cur != NULL)
	//{
	if ((!xmlStrcmp(cur->name, (const xmlChar *)rootNode))) {
		result[i++] = parseNode(doc, cur, childNode);
	}
	//cur = cur->next;
	//}

	xmlFreeDoc(doc);

	for (j = 0; j < i; j++)
		printf("%s\n", result[j]);

	return result;
}

/*
 * Get attribute value
 *
 * @node: get attribute from @node
 * @name: attribure's name
 */
static xmlChar *getAttributeFunc(xmlNodePtr node, const xmlChar * name)
{

	xmlChar *value;

	value = xmlGetProp(node, name);

	return value;
}

static xmlChar *getAttribute(xmlNodePtr node, const xmlChar * nodename)
{
	xmlChar *key = (xmlChar *) malloc(1000 * sizeof(xmlChar));
	memset(key, 0, 1000);

	node = node->xmlChildrenNode;

	while (node != NULL) {
		if ((!xmlStrcmp(node->name, (const xmlChar *)nodename))) {
			sprintf(key + strlen(key), "%s", getAttributeFunc(node, "id"));
			sprintf(key + strlen(key), ",%s;", getAttributeFunc(node, "status"));
		}

		node = node->next;
	}

	return key;
}

char *parse_session_attribute(char *docString)
{
	xmlDocPtr doc;
	xmlChar *xpath;
	xmlNodeSetPtr nodeset;
	xmlXPathObjectPtr result;
	char *retValue;
	int i;
	xmlChar *out;

	retValue = (char *)calloc(1024, sizeof(char));
	xpath = (xmlChar *) "//Session";
	doc = xmlParseDoc(docString);

	/* Get "Session" node */
	result = getnodeset(doc, xpath);

	/* Get Session's attribute
	 * Return: Alias1,ID1; Alias2,ID2;...
	 * */
	if (result) {
		nodeset = result->nodesetval;
		for (i = 0; i < nodeset->nodeNr; i++) {
			out = xmlGetProp(nodeset->nodeTab[i], "Alias");
			sprintf(retValue, "%s", out);
			out = xmlGetProp(nodeset->nodeTab[i], "ID");
			sprintf(retValue + strlen(retValue), ",%s;", out);
			xmlFree(out);
		}

		xmlXPathFreeObject(result);
	}

	xmlFreeDoc(doc);
	xmlCleanupParser();

	return retValue;
}

char *parse_peer_attribute(char *docString)
{
	xmlDocPtr doc;
	xmlChar *xpath;
	xmlNodeSetPtr nodeset;
	xmlXPathObjectPtr result;
	char *retValue;
	int i;
	xmlChar *out;

	retValue = (char *)calloc(1024, sizeof(char));
	xpath = (xmlChar *) "//peerID";
	doc = xmlParseDoc(docString);

	/* Get "Session" node */
	result = getnodeset(doc, xpath);

	/* Get Session's attribute
	 * Return: Alias1,ID1; Alias2,ID2;...
	 * */
	if (result) {
		nodeset = result->nodesetval;
		for (i = 0; i < nodeset->nodeNr; i++) {
			out = xmlGetProp(nodeset->nodeTab[i], "ID");
			sprintf(retValue + strlen(retValue), "%s,", out);
			//out = xmlGetProp(nodeset->nodeTab[i], "ID");
			//sprintf (retValue + strlen(retValue), ",%s;", out);
			//xmlFree(out);
		}

		xmlXPathFreeObject(result);
	}

	xmlFreeDoc(doc);
	xmlCleanupParser();

	return retValue;
}

/*
 * Now, just suppose 1 node in xml string
 * */
void parse_xml_node_content(const char *docString, const char *node, char *out)
{
	xmlDocPtr doc;
	xmlChar *xpath;
	xmlNodeSetPtr nodeset;
	xmlXPathObjectPtr result;
	xmlChar *keyword;
	xmlChar *docStr;
	int i;

	docStr = (xmlChar *) calloc(2000, sizeof(xmlChar));
	keyword = (xmlChar *) calloc(2000, sizeof(xmlChar));
	xpath = (xmlChar *) calloc(2000, sizeof(xmlChar));
	doc = (xmlDocPtr) calloc(1, sizeof(xmlDocPtr));

	printf("\n  doc = %d \n", doc);

	sprintf(xpath, "//%s", node);
	strncpy(docStr, docString, strlen(docString));

	if (!doc) {
		puts("xmlDocPtr = NULL");
		exit(EXIT_FAILURE);
	} else {
		doc = xmlParseDoc(docStr);
	}

	/* Get "Session" node */
	result = getnodeset(doc, xpath);

	/* Get Session's attribute
	 * Return: Alias1,ID1; Alias2,ID2;...
	 * */
	result = getnodeset(doc, xpath);
	if (result) {
		nodeset = result->nodesetval;
		for (i = 0; i < nodeset->nodeNr; i++) {
			keyword = xmlNodeListGetString(doc, nodeset->nodeTab[i]->xmlChildrenNode, 1);
			printf("\n%s\n", keyword);
		}

		xmlXPathFreeObject(result);
	}

	strncpy(out, keyword, strlen(keyword));

	xmlFreeDoc(doc);
	xmlCleanupParser();
	xmlFree(keyword);
	xmlFree(xpath);
}
