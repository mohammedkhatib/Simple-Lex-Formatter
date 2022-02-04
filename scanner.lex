/*Definitions*/
%{
  #include "AttributesNode.h"
  #include <stdio.h>
  #include "CommentList.h"
  #include <stdbool.h>
  #include "parser.tab.h"
  #include "TokenList.h"
  #include "CommentList.h"
  #include "GlobalTable.h"
  #include "PositionNode.h"
  #include "string.h"


  extern FILE* scanner_out_file;
  extern bool enablePrintingTokens;
  #define DEBUG_SCANNER enablePrintingTokens

  #ifdef DEBUG_SCANNER
  #define RETURN(x) return printDebug(x, #x)
  #else
  #define RETURN(x) return x
  #endif


  #define YY_USER_INIT \
  commentList = createCommentList(); \
  positionNode.startLine=1; \
  positionNode.startColumn=0; \
  positionNode.endLine=1; \
  positionNode.endColumn=0;             \
  globalTable = createGlobalTable();    \
  openLexDebug();


  extern bool allowDashComments;
  CommentList commentList;
  GlobalTable globalTable;
  PositionNode positionNode;

  #define YY_USER_ACTION updatePositions();

  #define PASS_TO_STATE(x) yyless(0);restorePositions();BEGIN(x)
  #define SKIP_RULE restorePositions();REJECT

  bool started = false;
  void openLexDebug();
  void updatePositions();
  void restorePositions();
  int printDebug();
  void lexError(const char*);
  AttributesNode storeTokenInfo(const char* customText);

  TokenList tokenList;
  char* currString;

  bool seenToken = false;
%}

%x processMultilineComment
%x inBlock
%x inEmbed
%x processSegmentStart
%x processSegmentStartMultilineComment
%x finishState
%x processString
%x processNewlineTerminatedWhitespace
%x processWhitespace
%x processEmbedStart
%x processEmbedEnd
%x processSegmentEdgeCase
%option yylineno
%option noyywrap
%option nodefault


whiteSpaces 							     	([\n\t\r ])+
SSComment    							     	(\/\/)(.)*
SDComment										(\-\-)(.)*
word											([^"\n\t\r #\/\(\)\[\]\{\}\;])+
/*Rules*/
%%

<INITIAL>{
  ^"<'"						{
                              BEGIN(processSegmentStart);
                              if(!started){
                                started=true;
                                RETURN(START);
                              }
                            }

  ^"'>"        				{
                              lexError("no matching start bracket");
                            }

  {whiteSpaces}				{}

  .							{}


  <<EOF>>										{
                              BEGIN(finishState);
                              if(started){
                                RETURN(END);
                              } else {
                                RETURN(EMPTY_INPUT);
                              }
                            }
}

<inBlock>{
  \"												{
                              //seenToken=true;
                              tokenList = createTokenList();
                              BEGIN(processString);
                            }

  ";"+											{
                              seenToken=false; RETURN(SC);
                            }

  "#:"/[ \t]*\n		                                {
                                                    yylval = storeTokenInfo("{");
                                                    BEGIN(processEmbedStart);
                                                    yylineno--;
                                                    RETURN(EMBED_START);
                                                  }
  "#:"/[ \t]*{SSComment}[ \t]*\n                  {
                                                    yylval = storeTokenInfo("{");
                                                    BEGIN(processEmbedStart);
                                                    yylineno--;
                                                    RETURN(EMBED_START);
                                                  }
  "#:"/[ \t]*{SDComment}[ \t]*\n                  {
                                                    if(!allowDashComments){
                                                      seenToken=true;
                                                      yylval = storeTokenInfo(NULL);
                                                      RETURN(TOKEN);
                                                    }
                                                    yylval = storeTokenInfo("{");
                                                    BEGIN(processEmbedStart);
                                                    yylineno--;
                                                    RETURN(EMBED_START);
                                                  }
  "#:"                                            {
                                                    //The #: has other items following it in the same line, thus processed as a token
                                                    seenToken=true;
                                                    yylval = storeTokenInfo(NULL);
                                                    RETURN(TOKEN);
                                                  }

  "/*"											{
                              BEGIN(processMultilineComment);
                            }

  "*/"											{
                              yylval = storeTokenInfo(NULL);
                              RETURN(TOKEN);
                            }

  "/"|"#"										{
                              yylval = storeTokenInfo(NULL);
                              RETURN(TOKEN);
                            }

  "("         						  {
                              seenToken=false;
                              yylval = storeTokenInfo(NULL);
                              RETURN(LPAREN);
                            }

  ")"							          {
                              seenToken=true;
                              yylval = storeTokenInfo(NULL);
                              RETURN(RPAREN);
                            }

  "{"         							{
                              seenToken=false;
                              yylval = storeTokenInfo(NULL);
                              RETURN(LBRACE);
                            }

  "}"							          {
                              seenToken=true;
                              yylval = storeTokenInfo(NULL);
                              RETURN(RBRACE);
                            }

  "["							          {
                              seenToken=false;
                              yylval = storeTokenInfo(NULL);
                              RETURN(LBRACKET);
                            }

  "]"						            {
                              seenToken=true;
                              yylval = storeTokenInfo(NULL);
                              RETURN(RBRACKET);
                            }

  ^"<'"											{
                              lexError("start bracket in code block");
                            }

  ^"'>"											{
                              BEGIN(INITIAL);
                            }

  {SSComment}  		          {
                              addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                            }

  {SDComment}  		          {
                              if(!allowDashComments){
                                SKIP_RULE;
                              } else {
                                addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                              }
                            }

  {word}					          {
                              seenToken=true;
                              yylval = storeTokenInfo(NULL);
                              RETURN(TOKEN);
                            }

  [\n\r\t ]*\n						  {
                              BEGIN(processNewlineTerminatedWhitespace);
                            }

  {whiteSpaces}							{
                              BEGIN(processWhitespace);
                            }

  <<EOF>>										{
                              lexError("unclosed block");
                            }
}

<inEmbed>{
  ([\t ])*end([\t ])*#.*    {
                              PASS_TO_STATE(processEmbedEnd);
                            }

  .*												{
                              RETURN(EMB_LINE);
                            }

  [\n\r]									  {}

}

<processEmbedEnd>{
  [\t ]+                    {}

  "end"[\t ]*"#"            {
                              BEGIN(inBlock);
                              yylval = storeTokenInfo("}");
							                seenToken=true;
                              RETURN(EMBED_END);
                            }
}

<processSegmentStart>{
  "/*"										  {
                              BEGIN(processSegmentStartMultilineComment);
                            }

  {SSComment}  		          {
                              addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                            }

  {SDComment}  		          {
                              if(!allowDashComments){
                                SKIP_RULE;
                              } else {
                                addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                              }
                            }

  [\n\r]									  {
                              PASS_TO_STATE(inBlock);
                            }

  [ \t]+ 									  {
                            }

  [^ \n\r\t] 						    {
                              lexError("token after <'");
                            }
}

<processEmbedStart>{
  {SSComment}  		          {
                              addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                            }

  {SDComment}  		          {
                              addToCommentList(commentList ,yytext, positionNode.startLine, positionNode.startColumn);
                            }

  [\n\r]									  {
                              BEGIN(inEmbed);
                            }

  [ \t]+ 									  {
                            }

}

<processMultilineComment>{
  [\n\r]                    {
                            }

  [^*\n\r]*        			    {/* eat anything that's not a '*' */
                            }

  "*"+[^*/\n]*   				    {/* eat up '*'s not followed by '/'s */
                            }

  "*"+"/"        						{
                              BEGIN(processWhitespace);
                            }

}

<processSegmentStartMultilineComment>{
  [\n\r]									  {
                              BEGIN(processMultilineComment);
                            }

  [^*\n\r]*        					{
                              /* eat anything that's not a '*' */
                            }

  "*"+[^*/\n]*   						{
                              /* eat up '*'s not followed by '/'s */
                            }

  "*"+"/"        						{
                              BEGIN(processSegmentStart);
                            }
}

<processNewlineTerminatedWhitespace>{
  "<'"									    {
                              lexError("Start bracket in code block");
                            }

  "'>"									    {
                              BEGIN(INITIAL);
                            }

  (\/\/)								    {
                              PASS_TO_STATE(inBlock);
                            }

  (\-\-)								    {
                              if(!allowDashComments){
                                SKIP_RULE;
                              }
                              PASS_TO_STATE(inBlock);
                            }

  "/*"									    {
                              PASS_TO_STATE(inBlock);
                            }

  ")"|"}"|"]"               {
                              PASS_TO_STATE(inBlock);
                            }

  [^\n\r\t ;]							  {
                              PASS_TO_STATE(inBlock);
                              if(seenToken){
                                yylval = storeTokenInfo(" ");
                                RETURN(WHITESPACE);}
                            }

  ";"									      {
                              PASS_TO_STATE(inBlock);
                            }

  .                         {
                              printf("What the fuck");
                            }

}

<processWhitespace>{
  ^"<'"										  {
                              lexError("Start bracket in code block");
                            }

  ^"'>"										  {
                              BEGIN(INITIAL);
                            }

  (\/\/)								    {
                              PASS_TO_STATE(inBlock);
                            }

  (\-\-)								    {
                              if(!allowDashComments){
                                SKIP_RULE;
                              }
                              PASS_TO_STATE(inBlock);
                            }

  "/*"									    {
                              PASS_TO_STATE(inBlock);
                            }

  ")"|"}"|"]"               {
                              PASS_TO_STATE(inBlock);
                            }

  [^\n\r\t ;]							  {
                              PASS_TO_STATE(inBlock);
                              if(seenToken){
                                yylval = storeTokenInfo(" ");
                                RETURN(WHITESPACE);
                                }
                            }

  "<'"										  {
                              PASS_TO_STATE(processSegmentEdgeCase);
                              if(seenToken){
                                yylval = storeTokenInfo(" ");
                                RETURN(WHITESPACE);
                              } else {
                                seenToken=true;
                              }
                            }

  "'>"										  {
                              PASS_TO_STATE(processSegmentEdgeCase);
                              if(seenToken){
                                yylval = storeTokenInfo(" ");
                                RETURN(WHITESPACE);
                              } else {
                                seenToken=true;
                                }
                            }

  ";"									      {
                              PASS_TO_STATE(inBlock);
                            }

  .										      {
                              printf("What the fuck");
                          }

  [\n\r\t ]							    {}
}


<processSegmentEdgeCase>"<'"|"'>"					  {
                              BEGIN(inBlock);
                              yylval = storeTokenInfo(NULL);
                              RETURN(TOKEN);
                            }

<processString>\"	                    { /* saw closing quote - all done */
                        		BEGIN(inBlock);
                        		currString = aggregateTokenList(tokenList);
                              yylval = createAttributesNode();
                              TokenList tokenList1 = createTokenList();
                              setTokenListAN(yylval, tokenList1);
							  addTokenToList(tokenList1,"\"",getStartLineTokenList(tokenList),getStartColumnTokenList(tokenList),0,0);
							  SimpleForm simpleForm = createSimpleForm(currString,getStartLineTokenList(tokenList),getStartColumnTokenList(tokenList)
                                      ,getLastLineTokenList(tokenList),getlastColumnTokenList(tokenList),NULL);
                              int res = addSimpleFormToGlobalTable(globalTable, simpleForm);
							  addSimpleFormTokenToList(tokenList1, res);
                int temp = res;
                int count = 0;
                while(temp){
                  temp/=16;
                  count++;
                }
                addFragmentToTokenList(tokenList1, positionNode.endLine,positionNode.endColumn-1, 3+count);
							  addTokenToList(tokenList1,yytext,0,0,positionNode.endLine,positionNode.endColumn);
                              destroyTokenList(tokenList);
                              seenToken=true;
                              RETURN(STRING);
                            }

<processString>\n	                    {
                    			   lexError("Unterminated String Constant\n");
                    			  }

<processString>\\n                    {
                              char s[2];s[0]='\n';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\f                    {
                              char s[2];s[0]='\f';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\t                    {
                              char s[2];s[0]='\t';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\r                    {
                              char s[2];s[0]='\r';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\\"                   {
                              char s[2];s[0]='\"';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\\\                   {
                              char s[2];s[0]='\\';s[1]=0;addTokenToList(tokenList,s,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
                            }

<processString>\\[ \t]*\n             {}

<processString>[^\\\n\"]+	            {
	                           addTokenToList(tokenList,yytext,positionNode.startLine,positionNode.startColumn,positionNode.endLine,positionNode.endColumn);
	                          }
%%

void updatePositions(){
    positionNode.prevStartLine = positionNode.startLine;
    positionNode.prevStartColumn = positionNode.startColumn;
    positionNode.prevEndLine = positionNode.endLine;
    positionNode.prevEndColumn = positionNode.endColumn;
    positionNode.startLine = positionNode.endLine;
    positionNode.startColumn = positionNode.endColumn;
    if (positionNode.startLine == yylineno)
    {
        positionNode.endColumn += yyleng;
    }
    else{
        positionNode.endColumn = yytext + yyleng - (strrchr(yytext, '\n') ? strrchr(yytext, '\n') : yytext) - 1;
        positionNode.endLine = yylineno;
    }
}

void restorePositions(){
    positionNode.startLine = positionNode.prevStartLine;
    positionNode.startColumn = positionNode.prevStartColumn;
    positionNode.endLine = positionNode.prevEndLine;
    positionNode.endColumn = positionNode.prevEndColumn;
}

AttributesNode storeTokenInfo(const char* customText){
  AttributesNode res = createAttributesNode();
  TokenList tokenList = createTokenList();
  setTokenListAN(res, tokenList);
  const char* tokenText = customText ? customText : yytext;
  addTokenToList(tokenList, tokenText, positionNode.startLine, positionNode.startColumn, positionNode.endLine, positionNode.endColumn);
  return res;
}

void lexError(const char* errMsg){
	fprintf( stderr, "Lex Error! %s at line %d\n",errMsg,yylineno);
	exit(400);
}

int printDebug(int token, char *s) {
  fprintf(scanner_out_file, "token : %s, text: %s ,line: %d\n", s,yytext, yylineno);
  return token;
}
