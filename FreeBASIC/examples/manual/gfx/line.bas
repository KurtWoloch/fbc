'' examples/manual/gfx/line.bas
''
'' NOTICE: This file is part of the FreeBASIC Compiler package and can't
''         be included in other distributions without authorization.
''
'' See Also: http://www.freebasic.net/wiki/wikka.php?wakka=KeyPgLinegraphics
'' --------

'' draws a diagonal red line with a white box, and waits for 3 seconds
Screen 13
Line (20, 20)-(300, 180), 4
Line (140, 80)-(180, 120), 15, b
Sleep 3000