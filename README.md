# mindbg
Small yet advanced debugger for CC:T
<img width="1908" height="1083" alt="debugger" src="https://github.com/user-attachments/assets/f08e13fa-bf94-4f24-aacc-29cd06308845" />

## Usage
### Running step/s
Running `step` or `s` executes the current line, visible on \[DEBUG]

### Running continue/c
Running `continue` or `c` will execute without stopping until a `__MINDBG_HALT()` is encountered. You can define `__MINDBG_HALT` as an empty function anywhere in your code.

### Running until/u
Running `until` or `u` will execute without stopping until a `MINDBG_HALT()` is encountered OR the line specified in the command has been reached. E.g. `until 156`

### Running print
To find the value of a variable mid-execution, run `print <expr>`. `print <expr>` accepts lua expressions, so you can do: `print math.floor(x) / 3 + 6`.

### Running set
To set the value of a variable mid-execution, run `set <value> = <expr>`. It accepts lua expressions, so you can do: `set x = { 15 / 6 + y }`

### Running bt
Running `bt` prints out a backtrace of the last executed functions.

### Running info
Running `info` prints out a detailed information sheet about the currently executing program.

### Running help
Running `help` will print out the available commands.
