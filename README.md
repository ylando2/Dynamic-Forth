Dynamic Forth version 0.1
=========================

Apologize
----------
First of all, I must admit that English is not my mother tongue so 
I apologize in advance for all the English mistake that I will make.

Introduction
------------
I was thinking about a minimal scripting language;
a really easy user friendly language for writing simple scripts.
I ask myself: What will happen if I mix Forth and Scheme.
What will happen if Forth language was a dynamic language 
with lambdas (blocks)? 
What will happen if functions will get values backward 
from the stack but the syntax will read the next words forward?
The result was a dynamic language that compile to Scheme that I named Dynamic-Forth.

To test my language you will have to do the following steps:

1. Type the following code in bash: 
         
        $ perl dynamic-forth.pl < test.df > test.scm 

2. Run test.scm with a Scheme compiler. 
 
About me
--------
I live in Israel. I am looking for a job.
If you have a serious job to offer me or if you want to contribute to my open source projects; please contact me; my email address is: ylando2@gmail.com 

Motivation
----------
I have the following use cases for my language:

* It can be used to replace the Linux dc command.
* We can compile the programs to guile scheme and use it instead of guile.

List of files
-------------
This directory contain the following files:

* dynamic-forth.pl - The compiler that compiles dynamic forth to scheme.
* API - The language API.
* TODO - A list of ideas to implement in the next versions of the language.
* GRAMMAR - The BNF grammar for my language.
* test.df - A program written in dynamic forth to test the compiler.

License
-------
Dynamic Forth is released under the MIT license.
