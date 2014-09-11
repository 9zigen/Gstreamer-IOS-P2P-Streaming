/*
 * parse xml string
 *
 * @docString: xml string
 * @root: root xml tag
 * @child: child xml tag
 *
 * return: array of nodes's content
 */
char **parseDoc (char *docString, char *root, char *child);
char *parse_session_attribute (char *docString);
char *parse_peer_attribute (char *docString);
void parse_xml_node_content (const char *docString,
							 const char *node, char *out);
