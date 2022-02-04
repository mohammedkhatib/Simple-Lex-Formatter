%{
    #include <stdio.h>
    #include <stdbool.h>
    #include <stdlib.h>
    extern int yylex();
    void printInit();
    void printNewLine();
    bool lastIsNewLine = false;
    int blocksCnt = 0;
%}


%x c_section
%x opt_section
%x rules_section
%x code_section
%option noyywrap
%option nodefault
whiteSpace 	([\t ])
whiteSpaces ([\t \n\r])
token       ([^\t {}%>\n\r])+


%%


<INITIAL>{
    "%{"       { BEGIN(c_section); printf("%s\n",yytext);}
    .*                  { printf("%s\n",yytext); }
    [\n\r]+             {}
}

<c_section>{
    (\n|\r)+                {printf("\n");}
                    {}
    "%}"                { printf("%s\n",yytext);
    BEGIN(opt_section);
    }
    "%"                 { printf("%s",yytext);}
    ">"                 { printf("%s",yytext);}
    "{"                 { printf("%s",yytext);}
    "}"                 { printf("%s",yytext);}
    
    ^{whiteSpace}*      { printf("\t"); }
    {token}             { printf("%s",yytext);}
    
    {whiteSpace}+       { printf(" ");}
    
}

<opt_section>{
    (\n|\r)+            { printf("\n");}
    "%%"\n              { printf("%s",yytext);BEGIN(rules_section);}
    .*                  { printf("%s",yytext);}
}

<rules_section>{
    (\n|\r)+            { printf("\n");}
    "%%"\n              { printf("%s\n",yytext);BEGIN(code_section);}
    "%"                 { printf("%s",yytext);}
    "{"\"               { printf("%s",yytext);}
    ">{"\"              { printf("%s",yytext);}
    ">"                 { printf("%s",yytext);}
    ">{"                { printf("%s",yytext);blocksCnt++;printNewLine();}
    "}"\"               { printf("%s",yytext);}
    ^{whiteSpace}*/"}"  { blocksCnt--;printInit();blocksCnt++;}
    "{"{whiteSpaces}+   { printNewLine();printf("{");blocksCnt++;printNewLine();}
    "{"                 { printf("{");blocksCnt++;}
    {whiteSpaces}+"}"{whiteSpaces}*
                        { blocksCnt--; printNewLine(); printf("}"); printNewLine();}
    "}"$                { blocksCnt--; printNewLine(); printf("}"); printNewLine();}
    "}"                 { blocksCnt--;printf("}");}
    ^{whiteSpace}*      { printInit();}
    {token}             { printf("%s",yytext);}
    {whiteSpace}+       { printf(" ");}
    
    
    }

<code_section>{
    (\n|\r)+            { printf("\n");}
    .*                  { printf("%s",yytext);}
}

%%

void printInit(){
    //printf("**the counter is %d**\n",blocksCnt);
    for(int i=0;i<blocksCnt;i++){
        printf("\t");
    }
}

void printNewLine(){
    printf("\n");
    printInit();
}

int main(){
    yylex();
    return 0;
}