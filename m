#!/usr/bin/env python

from subprocess import Popen, PIPE
import os
import sys
import glob
import py_compile
import symtable
import shutil
import re
import pprint

# order is important!
Files = [
        'support/closure-library/closure/goog/base.js',
        'support/closure-library/closure/goog/deps.js',
        'src/env.js',
        'src/builtin.js',
        'src/errors.js',
        'src/type.js',
        'src/function.js',
        'src/method.js',
        'src/object.js',
        'src/misceval.js',
        'src/abstract.js',
        'src/list.js',
        'src/str.js',
        'src/tuple.js',
        'src/dict.js',
        'src/long.js',
        'src/slice.js',
        'src/module.js',
        'src/generator.js',
        'src/file.js',
        'src/ffi.js',
        'src/wrapped_object.js',

        'src/tokenize.js',
        'gen/parse_tables.js',
        'src/parser.js',
        'gen/astnodes.js',
        'src/ast.js',
        'src/symtable.js',
        'src/compile.js',
        'src/import.js',
        ("support/jsbeautify/beautify.js", 'test'),
        ]

TestFiles = [
        'test/sprintf.js',
        "test/json2.js",
        "test/test.js"
        ]
DebugFiles = TestFiles[:-1]

def isClean():
    out, err = Popen("hg status", shell=True, stdout=PIPE).communicate()
    return out == ""

def getTip():
    out, err = Popen("hg tip", shell=True, stdout=PIPE).communicate()
    return out.split("\n")[0].split(":")[2].strip()

def getFileList(type):
    ret = []
    for f in Files:
        if isinstance(f, tuple):
            if f[1] == type:
                ret.append(f[0])
        else:
            if "*" in f:
                for g in glob.glob(f):
                    ret.append(f)
            else:
                ret.append(f)
    return ret

if sys.platform == "win32":
    jsengine = "support\\d8\\d8.exe --trace_exception --debugger"
    nul = "nul"
    crlfprog = os.path.join(os.path.split(sys.executable)[0], "Tools/Scripts/crlf.py")
else:
    jsengine = "support/d8/d8 --trace_exception --debugger"
    nul = "/dev/null"
    crlfprog = None

#jsengine = "rhino"

def test():
    """runs the unit tests."""
    os.system("%s %s %s" % (
        jsengine,
        ' '.join(getFileList('test')),
        ' '.join(TestFiles)))

def buildDebugBrowser():
    tmpl = """
<!DOCTYPE HTML>
<html>
    <head>
        <meta http-equiv="X-UA-Compatible" content="IE=edge" >
        <title>Skulpt test</title>
        <link rel="stylesheet" href="../closure-library/closure/goog/demos/css/demo.css"> 
        <link rel="stylesheet" href="../closure-library/closure/goog/css/menu.css"> 
        <link rel="stylesheet" href="../closure-library/closure/goog/css/menuitem.css"> 
        <link rel="stylesheet" href="../closure-library/closure/goog/css/menuseparator.css"> 
        <link rel="stylesheet" href="../closure-library/closure/goog/css/combobox.css"> 
        <style>
            .type { font-size:14px; font-weight:bold; font-family:arial; background-color:#f7f7f7; text-align:center }
        </style>

%s
    </head>

    <body onload="testsMain()">
        <table>
        <tr>
            <td>
                <div id="one-test" class="use-arrow"></div>
            </td>
        </tr>
        <tr>
            <td>
            <pre id="output"></pre>
            </td>
            <td>
            <span id="canv"></span>
            </td>
        </tr>
    </body>
</html>
"""
    if not os.path.exists("support/tmp"):
        os.mkdir("support/tmp")
    buildVFS()
    scripts = []
    for f in getFileList('test') + ["test/browser-stubs.js", "support/tmp/vfs.js", "gen/closure_ctor_hack.js", "gen/debug_import_all_closure.js"] + TestFiles:
        scripts.append('<script type="text/javascript" src="%s"></script>' %
                os.path.join('../..', f))
 
    with open("support/tmp/test.html", "w") as f:
        print >>f, tmpl % '\n'.join(scripts)

    if sys.platform == "win32":
        os.system("start support/tmp/test.html")
    else:
        os.system("gnome-open support/tmp/test.html")

def buildVFS():
    """ build a silly virtual file system to support 'read'"""
    print ". Slurping test data"
    with open("support/tmp/vfs.js", "w") as out:
        print >>out, "VFSData = {"
        all = []
        for root in ("test", "src/builtin"):
            for dirpath, dirnames, filenames in os.walk(root):
                for filename in filenames:
                    f = os.path.join(dirpath, filename)
                    if ".svn" in f: continue
                    if ".swp" in f: continue
                    if ".pyc" in f: continue
                    data = open(f, "rb").read()
                    all.append("'%s': '%s'" % (f.replace("\\", "/"), data.encode("hex")))
        print >>out, ",\n".join(all)
        print >>out, "};"
        print >>out, """
function readFromVFS(fn)
{
    var hexToStr = function(str)
    {
        var ret = "";
        for (var i = 0; i < str.length; i += 2)
            ret += unescape("%" + str.substr(i, 2));
        return ret;
    }
    if (VFSData[fn] === undefined) throw "file not found: " + fn;
    return hexToStr(VFSData[fn]);
}
"""

def buildBrowserTests():
    """combine all the tests data into something we can run from a browser
    page (so that it can be tested in the various crappy engines)

    we want to use the same code that the command line version of the tests
    uses so we stub the d8 functions to push to the browser."""

    outfn = "doc/static/browser-test.js"
    out = open(outfn, "w")

    print >>out, """
window.addevent('onload', function(){
"""

    # stub the d8 functions we use
    print >>out, """
function read(fn)
{
    var hexToStr = function(str)
    {
        var ret = "";
        for (var i = 0; i < str.length; i += 2)
            ret += unescape("%%" + str.substr(i, 2));
        return ret;
    }
    if (VFSData[fn] === undefined) throw "file not found: " + fn;
    return hexToStr(VFSData[fn]);
}
var SkulptTestRunOutput = '';
function print()
{
    var out = document.getElementById("output");
    for (var i = 0; i < arguments.length; ++i)
    {
        out.innerHTML += arguments[i];
        SkulptTestRunOutput += arguments[i];
        out.innerHTML += " ";
        SkulptTestRunOutput += " ";
    }
    out.innerHTML += "<br/>"
    SkulptTestRunOutput += "\\n";
}

function quit(rc)
{
    var out = document.getElementById("output");
    if (rc === 0)
    {
        out.innerHTML += "<font color='green'>OK</font>";
    }
    else
    {
        out.innerHTML += "<font color='red'>FAILED</font>";
    }
    out.innerHTML += "<br/>Saving results...";
    var sendData = JSON.encode({
        browsername: BrowserDetect.browser,
        browserversion: BrowserDetect.version,
        browseros: BrowserDetect.OS,
        version: '%s',
        rc: rc,
        results: SkulptTestRunOutput
    });
    var results = new Request.JSON({
        url: '/testresults',
        method: 'post',
        onSuccess: function() { out.innerHTML += "<br/>Results saved."; },
        onFailure: function() { out.innerHTML += "<br/>Couldn't save results."; }
    });
    results.send(sendData);
}
""" % getTip()

    for f in ["test/browser-detect.js"] + getFileList('test') + TestFiles:
        print >>out, open(f).read()

    print >>out, """
});
"""
    out.close()
    print ". Built %s" % outfn


def dist():
    """builds a 'shippable' version of Skulpt.
    
    this is all combined into one file, tests run, jslint'd, compressed.
    """

    if not isClean():
        print "WARNING: working directory not clean (according to 'hg status')"
        #raise SystemExit()

    label = getTip()

    print ". Nuking old dist/"
    os.system("rm -rf dist/")
    if not os.path.exists("dist"): os.mkdir("dist")

    """
    print ". Writing combined version..."
    combined = ''
    linemap = open("dist/linemap.txt", "w")
    curline = 1
    for file in getFileList('dist'):
        curfiledata = open(file).read()
        combined += curfiledata
        print >>linemap, "%d:%s" % (curline, file)
        curline += len(curfiledata.split("\n")) - 1
    linemap.close()
    """

    # make combined version
    #uncompfn = "dist/skulpt-uncomp.js"
    compfn = "dist/skulpt.js"
    #open(uncompfn, "w").write(combined)
    #os.system("chmod 444 dist/skulpt-uncomp.js") # just so i don't mistakenly edit it all the time

    buildBrowserTests()

    """
    # run jslint on uncompressed
    print ". Running JSLint on uncompressed..."
    ret = os.system("python support/jslint/wrapper.py %s dist/linemap.txt" % uncompfn)
    os.unlink("dist/linemap.txt")
    if ret != 0:
        print "JSLint complained."
        raise SystemExit()
    """

    # run tests on uncompressed
    print ". Running tests on uncompressed..."
    ret = os.system("%s %s %s" % (jsengine, ' '.join(getFileList('dist')), ' '.join(TestFiles)))
    if ret != 0:
        print "Tests failed on uncompressed version."
        raise SystemExit()

    # compress
    uncompfiles = ' '.join(['--js ' + x for x in getFileList('dist')])
    print ". Compressing..."
    ret = os.system("java -jar support/closure-compiler/compiler.jar --define goog.DEBUG=false --output_wrapper \"(function(){%%output%%}());\" --compilation_level ADVANCED_OPTIMIZATIONS --jscomp_error accessControls --jscomp_error checkRegExp --jscomp_error checkTypes --jscomp_error checkVars --jscomp_error deprecated --jscomp_off fileoverviewTags --jscomp_error invalidCasts --jscomp_error missingProperties --jscomp_error nonStandardJsDocs --jscomp_error strictModuleDepCheck --jscomp_error undefinedVars --jscomp_error unknownDefines --jscomp_error visibility %s --js_output_file %s" % (uncompfiles, compfn)) 
    # --jscomp_error accessControls --jscomp_error checkRegExp --jscomp_error checkTypes --jscomp_error checkVars --jscomp_error deprecated --jscomp_error fileoverviewTags --jscomp_error invalidCasts --jscomp_error missingProperties --jscomp_error nonStandardJsDocs --jscomp_error strictModuleDepCheck --jscomp_error undefinedVars --jscomp_error unknownDefines --jscomp_error visibility
    if ret != 0:
        print "Couldn't run closure-compiler."
        raise SystemExit()

    # run tests on compressed
    #print ". Running tests on compressed..."
    #ret = os.system("%s %s %s" % (jsengine, compfn, ' '.join(TestFiles)))
    #if ret != 0:
        #print "Tests failed on compressed version."
        #raise SystemExit()

    ret = os.system("cp %s dist/tmp.js" % compfn)
    if ret != 0:
        print "Couldn't copy for gzip test."
        raise SystemExit()

    ret = os.system("gzip -9 dist/tmp.js")
    if ret != 0:
        print "Couldn't gzip to get final size."
        raise SystemExit()

    size = os.path.getsize("dist/tmp.js.gz")
    os.unlink("dist/tmp.js.gz")

    # update doc copy
    """
    ret = os.system("cp %s doc/static/skulpt.js" % compfn)
    ret |= os.system("cp %s doc/static/skulpt-uncomp.js" % uncompfn)
    if ret != 0:
        print "Couldn't copy to docs dir."
        raise SystemExit()
        """

    # all good!
    print ". Wrote %s." % compfn
    print ". gzip of compressed: %d bytes" % size

def regenparser():
    """regenerate the parser/ast source code"""
    if not os.path.exists("gen"): os.mkdir("gen")
    os.chdir("src/pgen/parser")
    os.system("python main.py ../../../gen/parse_tables.js")
    os.chdir("../ast")
    os.system("python asdl_js.py Python.asdl ../../../gen/astnodes.js")
    os.chdir("../../..")
    # sanity check that they at least parse
    #os.system(jsengine + " support/closure-library/closure/goog/base.js src/env.js src/tokenize.js gen/parse_tables.js gen/astnodes.js")

def regenasttests():
    """regenerate the ast test files by running our helper script via real python"""
    for f in glob.glob("test/run/*.py"):
        transname = f.replace(".py", ".trans")
        os.system("python test/astppdump.py %s > %s" % (f, transname))
        forcename = f.replace(".py", ".trans.force")
        if os.path.exists(forcename):
            shutil.copy(forcename, transname)
        if crlfprog:
            os.system("python %s %s" % (crlfprog, transname))


def regenruntests():
    """regenerate the test data by running the tests on real python"""
    for f in glob.glob("test/run/*.py"):
        os.system("python %s > %s.real 2>&1" % (f, f))
        forcename = f + ".real.force"
        if os.path.exists(forcename):
            shutil.copy(forcename, "%s.real" % f)
        if crlfprog:
            os.system("python %s %s.real" % (crlfprog, f))
    for f in glob.glob("test/interactive/*.py"):
        p = Popen("python -i > %s.real 2>%s" % (f, nul), shell=True, stdin=PIPE)
        p.communicate(open(f).read() + "\004")
        forcename = f + ".real.force"
        if os.path.exists(forcename):
            shutil.copy(forcename, "%s.real" % f)
        if crlfprog:
            os.system("python %s %s.real" % (crlfprog, f))



def symtabdump(fn):
    if not os.path.exists(fn):
        print "%s doesn't exist" % fn
        raise SystemExit()
    text = open(fn).read()
    mod = symtable.symtable(text, os.path.split(fn)[1], "exec")
    def getidents(obj, indent=""):
        ret = ""
        ret += """%sSym_type: %s
%sSym_name: %s
%sSym_lineno: %s
%sSym_nested: %s
%sSym_haschildren: %s
""" % (
        indent, obj.get_type(),
        indent, obj.get_name(),
        indent, obj.get_lineno(),
        indent, obj.is_nested(),
        indent, obj.has_children())
        if obj.get_type() == "function":
            ret += "%sFunc_params: %s\n%sFunc_locals: %s\n%sFunc_globals: %s\n%sFunc_frees: %s\n" % (
                    indent, sorted(obj.get_parameters()),
                    indent, sorted(obj.get_locals()),
                    indent, sorted(obj.get_globals()),
                    indent, sorted(obj.get_frees()))
        elif obj.get_type() == "class":
            ret += "%sClass_methods: %s\n" % (
                    indent, sorted(obj.get_methods()))
        ret += "%s-- Identifiers --\n" % indent
        for ident in sorted(obj.get_identifiers()):
            info = obj.lookup(ident)
            ret += "%sname: %s\n  %sis_referenced: %s\n  %sis_imported: %s\n  %sis_parameter: %s\n  %sis_global: %s\n  %sis_declared_global: %s\n  %sis_local: %s\n  %sis_free: %s\n  %sis_assigned: %s\n  %sis_namespace: %s\n  %snamespaces: [\n%s  %s]\n" % (
                    indent, info.get_name(),
                    indent, info.is_referenced(),
                    indent, info.is_imported(),
                    indent, info.is_parameter(),
                    indent, info.is_global(),
                    indent, info.is_declared_global(),
                    indent, info.is_local(),
                    indent, info.is_free(),
                    indent, info.is_assigned(),
                    indent, info.is_namespace(),
                    indent, '\n'.join([getidents(x, indent + "    ") for x in info.get_namespaces()]),
                    indent
                    )
        return ret
    return getidents(mod)

def regensymtabtests():
    """regenerate the test data by running the symtab dump via real python"""
    for fn in glob.glob("test/run/*.py"):
        outfn = "%s.symtab" % fn
        f = open(outfn, "wb")
        f.write(symtabdump(fn))
        f.close()

def upload():
    """uploads doc to GAE (stub app for static hosting, mostly)"""
    print "you probably don't want to do that right now"
    return
    ret = os.system("python2.5 support/tmp/google_appengine/appcfg.py update doc")
    if ret != 0:
        print "Couldn't upload."
        raise SystemExit()

def run(fn, shell=""):
    if not os.path.exists(fn):
        print "%s doesn't exist" % fn
        raise SystemExit()
    if not os.path.exists("support/tmp"):
        os.mkdir("support/tmp")
    f = open("support/tmp/run.js", "w")
    modname = os.path.splitext(os.path.basename(fn))[0]
    f.write("""
var input = read('%s');
print("-----");
print(input);
print("-----");
Sk.syspath = ["%s"];
var module = Sk.importModule("%s", true);
print("-----");
    """ % (fn, os.path.split(fn)[0], modname))
    f.close()
    os.system("%s %s %s support/tmp/run.js" %
            (jsengine,
                shell,
                ' '.join(getFileList('test'))))

def runopt(fn):
    if not os.path.exists(fn):
        print "%s doesn't exist" % fn
        raise SystemExit()
    f = open("support/tmp/run.js", "w")
    f.write("""
var input = read('%s');
eval(Skulpt.compileStr('%s', input));
    """ % (fn, fn))
    f.close()
    os.system(jsengine + " --nodebugger dist/skulpt.js support/tmp/run.js")

def shell(fn):
    run(fn, "--shell")

def parse(fn):
    if not os.path.exists(fn):
        print "%s doesn't exist" % fn
        raise SystemExit()
    f = open("support/tmp/parse.js", "w")
    f.write("""
var input = read('%s');
var cst = Skulpt._parse('%s', input);
print(astDump(Skulpt._transform(cst)));
    """ % (fn, fn))
    f.close()
    os.system("%s %s test/footer_test.js %s support/tmp/parse.js" % (
        jsengine,
        ' '.join(getFileList('test')),
        ' '.join(DebugFiles)))

def nrt():
    """open a new run test"""
    for i in range(100000):
        fn = "test/run/t%02d.py" % i
        disfn = fn + ".disabled"
        if not os.path.exists(fn) and not os.path.exists(disfn):
            os.system("vim " + fn)
            print "don't forget to ./m regentests"
            break

def vmwareregr(names):
    """todo; not working yet.
    
    run unit tests via vmware on a bunch of browsers"""

    xp = "/data/VMs/xpsp3/xpsp3.vmx"
    ubu = "/data/VMs/ubu910/ubu910.vmx"
    # apparently osx isn't very vmware-able. stupid.

    class Browser:
        def __init__(self, name, vmx, guestloc):
            self.name = name
            self.vmx = vmx
            self.guestloc = guestloc

    browsers = [
            Browser("ie7-win", xp, "C:\\Program Files\\Internet Explorer\\iexplore.exe"),
            Browser("ie8-win", xp, "C:\\Program Files\\Internet Explorer\\iexplore.exe"),
            Browser("chrome3-win", xp, "C:\\Documents and Settings\\Administrator\\Local Settings\\Application Data\\Google\\Chrome\\Application\\chrome.exe"),
            Browser("chrome4-win", xp, "C:\\Documents and Settings\\Administrator\\Local Settings\\Application Data\\Google\\Chrome\\Application\\chrome.exe"),
            Browser("ff3-win", xp, "C:\\Program Files\\Mozilla Firefox\\firefox.exe"),
            Browser("ff35-win", xp, "C:\\Program Files\\Mozilla Firefox\\firefox.exe"),
            #Browser("safari3-win", xp,
            #Browser("safari4-win", xp,
            #"ff3-osx": osx,
            #"ff35-osx": osx,
            #"safari3-osx": osx,
            #"safari4-osx": osx,
            #"ff3-ubu": ubu,
            #"chromed-ubu": ubu,
            ]


def regengooglocs():
    """scans the closure library and builds an import-everything file to be
    used during dev. """

    # from calcdeps.py
    prov_regex = re.compile('goog\.provide\s*\(\s*[\'\"]([^\)]+)[\'\"]\s*\)')
    
    # walk whole tree, find all the 'provide's in a file, and note the location
    root = "support/closure-library/closure"
    modToFile = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for filename in filenames:
            f = os.path.join(dirpath, filename)
            if ".svn" in f: continue
            if os.path.splitext(f)[1] == ".js":
                contents = open(f).read()
                for prov in prov_regex.findall(contents):
                    modToFile[prov] = f.lstrip(root)

    with open("gen/debug_import_all_closure.js", "w") as glf:
        keys = modToFile.keys()
        keys.sort()
        for m in keys:
            if "demos." in m: continue
            if not m.startswith("goog."): continue
            print >>glf, "goog.require('%s');" % m

def regenclosurebindings():
    """uses jsdoc-toolkit to scan closure library. generates a table of
    constructors that we use to call them properly. could perhaps generate more
    complex ffi in the future. or maybe just grep ourselves because
    jsdoc-toolkit is so freakin' slow.
    
    see publish.js in the closure-wrap-gen dir."""

    os.system("java -jar support/closure-wrap-gen/jsdoc-toolkit/jsrun.jar support/closure-wrap-gen/jsdoc-toolkit/app/run.js support/closure-library/closure/goog/* -t=support/closure-wrap-gen/skulptwrap > support/tmp/closure_ctor_hack.txt")

    with open("support/tmp/closure_ctor_hack.txt") as f:
        with open("gen/closure_ctor_hack.js", "w") as out:
            print >>out, "Sk.closureCtorHack = function() {"

            for l in f.readlines():
                # strip some junk and output the rest that we actual make in publish.js
                if l.startswith(">>"): continue
                if ", not found." in l: continue
                if "-tempCtor" in l: continue
                if "-nodeCreator" in l: continue
                if "-temp" in l: continue
                if "warnings." in l: continue

                out.write(l)
            print >>out, "};"


if __name__ == "__main__":
    if sys.platform == 'win32':
        os.system("cls")
    else:
        os.system("clear")
    def usage():
        print "usage: m {test|dist|regenparser|regentests|regenasttests|regenruntests|regensymtabtests|upload|nrt|run|runopt|parse|vmwareregr|browser|shell|debugbrowser|regenclosurebindings|vfs}"
        sys.exit(1)
    if len(sys.argv) < 2:
        cmd = "test"
    else:
        cmd = sys.argv[1]
    if cmd == "test":
        test()
    elif cmd == "dist":
        dist()
    elif cmd == "regengooglocs":
        regengooglocs()
    elif cmd == "regentests":
        regensymtabtests()
        regenasttests()
        regenruntests()
    elif cmd == "regensymtabtests":
        regensymtabtests()
    elif cmd == "run":
        run(sys.argv[2])
    elif cmd == "runopt":
        runopt(sys.argv[2])
    elif cmd == "parse":
        parse(sys.argv[2])
    elif cmd == "vmwareregr":
        parse(sys.argv[2])
    elif cmd == "regenparser":
        regenparser()
    elif cmd == "regenasttests":
        regenasttests()
    elif cmd == "regenruntests":
        regenruntests()
    elif cmd == "upload":
        upload()
    elif cmd == "nrt":
        nrt()
    elif cmd == "browser":
        buildBrowserTests()
    elif cmd == "debugbrowser":
        buildDebugBrowser()
    elif cmd == "regenclosurebindings":
        regenclosurebindings()
    elif cmd == "vfs":
        buildVFS()
    elif cmd == "shell":
        shell(sys.argv[2]);
    else:
        usage()
