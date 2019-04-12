package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaTable;
import com.opencsv.CSVReader;
import com.opencsv.CSVWriter;
import com.opencsv.ResultSetHelperService;
import com.opencsv.SQLWriter;
import org.jline.keymap.KeyMap;
import org.jline.utils.OSUtils;
import org.mozilla.universalchardet.UniversalDetector;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.math.BigInteger;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.TreeMap;
import java.util.concurrent.*;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;
import java.util.zip.InflaterInputStream;

public class Loader {

    public static String ReloadNextTime = "_init_";
    public static String root = "";
    public static String libPath;
    static LuaState lua;
    static Console console;
    private static Loader loader = null;
    KeyMap keyMap;
    KeyListner q = new KeyListner('q');
    Future sleeper;
    private volatile CallableStatement stmt = null;
    private Sleeper runner = new Sleeper();
    private volatile ResultSet rs;
    private IOException CancelError = new IOException("Statement is aborted.");

    private Loader() throws Exception {
        try {
            File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            root = f.getParentFile().getParent();
            libPath = root + File.separator + "lib" + File.separator;
            if (OSUtils.IS_WINDOWS) {
                String bit = System.getProperty("sun.arch.data.model");
                if (bit == null) bit = System.getProperty("com.ibm.vm.bitmode");
                libPath += (bit.equals("64") ? "x64" : "x86");
            } else if (OSUtils.IS_OSX) {
                libPath += "mac";
            } else {
                libPath += "linux";
            }
            String libs = System.getenv("LD_LIBRARY_PATH");
            addLibrary(libPath + (libs == null ? "" : File.pathSeparator + libs), true);
            System.setProperty("library.jansi.path", libPath);
            System.setProperty("jna.library.path", libPath);
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
        console = new Console(root + File.separator + "cache" + File.separator + "history.log");
        lua = LuaState.getMainLuaState();
        if (lua != null) console.setLua(lua);
        //Ctrl+D
        keyMap = console.reader.getKeys();
        //Interrupter.listen(this, event);
    }

    public String getRootPath() {
        return root;
    }

    public String getInputPath() {
        String separator = File.separator;
        return root + separator + "lua" + separator + "input.lua";
    }

    public static Loader get() throws Exception {
        if (loader == null) loader = new Loader();
        return loader;
    }

    public static Exception getRootCause(Exception e) {
        Throwable t = e.getCause();
        while (t != null && t.getCause() != null) t = t.getCause();
        return t == null ? e : new Exception(t);
    }

    public static void loadLua(Loader loader, String[] args) throws Exception {
        lua = new LuaState();
        lua.pushGlobal("loader", loader);
        console.isSubSystem = false;
        console.setLua(lua);
        String separator = File.separator;
        String input = root + separator + "lua" + separator + "input.lua";
        if (console.writer != null) {
            lua.pushGlobal("reader", console.reader);
            lua.pushGlobal("writer", console.writer);
            lua.pushGlobal("terminal", console.terminal);
            lua.pushGlobal("console", console);
            lua.pushGlobal("WORK_DIR", root + separator);
        }
        StringBuilder sb = new StringBuilder();
        String readline = "";
        BufferedReader br = new BufferedReader(new FileReader(new File(input)));
        while (br.ready()) {
            readline = br.readLine();
            sb.append(readline + "\n");
        }
        br.close();
        //System.out.println(asb.toString());
        lua.load(sb.toString(), input);
        if (ReloadNextTime != null && ReloadNextTime.equals("_init_")) ReloadNextTime = null;
        ArrayList<String> list = new ArrayList<>(args.length);
        if (ReloadNextTime != null) list.add("set database " + ReloadNextTime);
        for (int i = 0; i < args.length; i++) {
            if (ReloadNextTime != null && (args[i].toLowerCase().contains(" database ") || args[i].toLowerCase().contains(" platform ")))
                continue;
            list.add(args[i]);
        }
        ReloadNextTime = null;
        lua.call(list.toArray());
        lua.close();
        lua = null;
        System.gc();
    }

    public static void addLibrary(String s, Boolean isReplace) throws Exception {
        try {
            Field field = ClassLoader.class.getDeclaredField("usr_paths");
            field.setAccessible(true);
            TreeMap<String, Boolean> map = new TreeMap<>();
            for (String t : s.split(File.pathSeparator)) map.put(t, true);
            if (!isReplace) for (String t : (String[]) field.get(null)) map.put(t, true);
            String[] tmp = map.keySet().toArray(new String[0]);
            System.setProperty("java.library.path", String.join(File.pathSeparator, tmp));
            field.set(null, tmp);
        } catch (IllegalAccessException e) {
            throw new IOException("Failed to get permissions to set library path");
        } catch (NoSuchFieldException e) {
            System.setProperty("java.library.path", s);
            //throw new IOException("Failed to get field handle to set library path");
        }
    }

    public static void main(String[] args) throws Exception {
        Loader l = get();
        while (ReloadNextTime != null) loadLua(l, args);
        //console.threadPool.shutdown();
    }

    public static byte[] hexStringToByteArray(String s) {
        int len = s.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                    + Character.digit(s.charAt(i + 1), 16));
        }
        return data;
    }

    public void resetLua() {
        console.setLua(lua);
    }

    public void mkdir(String path) {
        new File(path).mkdirs();
    }

    public void addPath(String file) throws Exception {
        URLClassLoader classLoader = (URLClassLoader) lua.getClassLoader();
        Class<URLClassLoader> clazz = URLClassLoader.class;
        URL url = new URL("file:" + file);
        // Use reflection
        Method method = clazz.getDeclaredMethod("addURL", URL.class);
        method.setAccessible(true);
        method.invoke(classLoader, url);
        TreeMap<String, Boolean> map = new TreeMap();
        for (String s : (System.getProperty("java.class.path") + File.pathSeparator + file.replace(root, ".")).split(File.pathSeparator))
            map.put(s, true);
        System.setProperty("java.class.path", String.join(File.pathSeparator, map.keySet().toArray(new String[0])));
    }

    public void copyClass(String className) throws Exception {
        JavaAgent.copyFile(null, className.replace("\\.", "/"), null);
    }

    public void createJar(String[] classes, String location, String source) throws Exception {
        JavaAgent.createJar(classes, location, source);
    }

    public String dumpClass(String folder) throws Exception {
        String cp = System.getProperty("java.class.path");
        String stack = java.lang.management.ManagementFactory.getRuntimeMXBean().getName();
        String packageName = Loader.class.getPackage().getName() + ".FileDump";
        //packageName="sun.jvm.hotspot.tools.jcore.ClassDump";
        String sep = File.separator;
        stack = stack.split("@")[0];
        Pattern p = Pattern.compile("[\\\\/]jre.*", Pattern.CASE_INSENSITIVE);
        String java_home = p.matcher(System.getProperty("java.home")).replaceAll("");
        stack = String.format("java -cp \"%s%slib%s*%s\" -Dsun.jvm.hotspot.tools.jcore.outputDir=%s %s %s", java_home, sep, sep, cp, folder, packageName, stack);
        //System.out.println("Command: "+stack);
        return stack;
    }

    public void setCurrentResultSet(ResultSet res) {
        this.rs = res;
    }

    private void setExclusiveAndRemap(CSVWriter writer, String excludes, String[] remaps) {
        if (excludes != null && !excludes.trim().equals("")) {
            String[] ary = excludes.split(",");
            for (String column : ary) writer.setExclude(column, true);
        }
        if (remaps != null) {
            for (String column : remaps) {
                if (column == null || column.trim().equals("")) continue;
                String[] o = column.split("=", 2);
                writer.setRemap(o[0], o.length < 2 ? null : o[1]);
            }
        }
    }

    //copy from https://www.perumal.org/computing-oracle-sql_id-and-hash_value/
    public static String computeSQLIdFromText(String stmt) throws UnsupportedEncodingException, NoSuchAlgorithmException {

        /* Example
         *  Statement: SELECT 'Ram' ram_stmt FROM dual
         *  MD5 Hash with null terminator: 93bc072570a58c1f330166ab2d0a88d2
         *  Oracle SQL_ID: aqth16g98h2jd
         *  Address: 00000000826C6060
         *  Hash Value: 3532130861
         *  Hash Value Hex: D2880A2D
         *  MD5 Hash without null terminator: 93bc072570a58c1f330166ab2d0a88d2
         *  Exact Matching Signature: 4178266890746386855
         *  Exact Matching Signature Hex: 39FC2F9987B6D9A7
         *  MD5 Hash without null terminator for bound statement:
         *  Force Matching Signature: 16194980974160721469
         *  Force Matching Signature Hex: E0C021642D0F363D
         */

        // get bytes of the string supplied
        byte[] bytesOfStatement = stmt.getBytes(StandardCharsets.UTF_8); //should not use trim()
        byte[] bytesOfStatementWithNull = new byte[bytesOfStatement.length + 1]; // last bucket used for Null Terminator
        byte nullCharByte = 0x00; // get bytes of null terminator

        // Null terminator is lost or has no effect (Unicode \\u0000, \\U0000 or hex 0x00 or "\0")
        // on MD5 digest when you append to String
        // Hence add the byte value as a last element after cloning
        System.arraycopy(bytesOfStatement, 0, bytesOfStatementWithNull, 0, bytesOfStatement.length); // clone the array
        bytesOfStatementWithNull[bytesOfStatement.length] = nullCharByte; // add null terminator as last element

        // get the MD5 digest
        MessageDigest md = MessageDigest.getInstance("MD5");
        byte[] bytesFromMD5Digest = md.digest(bytesOfStatementWithNull);

        // convert the byte to hex format
        // and generate MD5 hash
        StringBuffer sbMD5HashHex32 = new StringBuffer();
        for (int i = 0; i < bytesFromMD5Digest.length; i++) {
            sbMD5HashHex32.append(Integer.toString((bytesFromMD5Digest[i] & 0xff) + 0x100, 16).substring(1));
        }

        // Obtain MD5 hash, split and reverse Q3 and Q4
        // Get 32 Hex Characters
        String strHex32Hash = sbMD5HashHex32.toString();

        // Reverse order of each of the 4 pairs of hex characters in Q3 and Q4
        // Q3 reverse
        String strHexQ3Reverse = strHex32Hash.substring(22, 24) + strHex32Hash.substring(20, 22)
                + strHex32Hash.substring(18, 20) + strHex32Hash.substring(16, 18);
        // Q4 reverse
        String strHexQ4Reverse = strHex32Hash.substring(30, 32) + strHex32Hash.substring(28, 30)
                + strHex32Hash.substring(26, 28) + strHex32Hash.substring(24, 26);
        // assemble lower 16 with reversed q3 and q4
        String strHexLower16Assembly = strHexQ3Reverse + strHexQ4Reverse;
        // convert to 64 bits of binary data
        String strBinary16Assembly = (new BigInteger(strHexLower16Assembly, 16).toString(2));

        // Left pad with zeros, if the length is less than 64
        StringBuffer sbBinary16mAssembly = new StringBuffer();
        for (int toLefPad = 64 - strBinary16Assembly.length(); toLefPad > 0; toLefPad--) {
            sbBinary16mAssembly.append('0');
        }
        sbBinary16mAssembly.append(strBinary16Assembly);
        strBinary16Assembly = sbBinary16mAssembly.toString();

        // Split the 64 bit string into 13 pieces
        // First split as 4 bit and remaining as 5 bits
        String alphabet = "0123456789abcdfghjkmnpqrstuvwxyz";
        String strPartBindaySplit;
        int intIndexOnAlphabet;
        StringBuffer sbSQLId = new StringBuffer();

        for (int i = 0; i < 13; i++) {
            // Split binary string into 13 pieces
            strPartBindaySplit = (i == 0 ? strBinary16Assembly.substring(0, 4)
                    : (i < 12 ? strBinary16Assembly.substring((i * 5) - 1, (i * 5) + 4)
                    : strBinary16Assembly.substring((i * 5) - 1)));
            // Index position on Alphabet
            intIndexOnAlphabet = Integer.parseInt(strPartBindaySplit, 2);
            // Stick 13 characters
            sbSQLId.append(alphabet.charAt(intIndexOnAlphabet));

        }

        return sbSQLId.toString();
    }

    public int ResultSet2CSV(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (CSVWriter writer = new CSVWriter(fileName)) {
                writer.setAsyncMode(aync);
                setExclusiveAndRemap(writer, excludes, remaps);
                int result = writer.writeAll(rs, true);
                return result - 1;
            }
        });
    }

    public int ResultSet2SQL(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (SQLWriter writer = new SQLWriter(fileName)) {
                writer.setAsyncMode(aync);
                writer.setFileHead(header);
                setExclusiveAndRemap(writer, excludes, remaps);
                int count = writer.writeAll2SQL(rs, "", 1500);
                return count;
            }
        });
    }

    public byte[] Base642Bytes(String base64) {
        return Base64.getDecoder().decode(base64.replaceAll("\\s+", ""));
    }

    public String Base64ZlibToText(String[] pieces) throws Exception {
        byte[] buff = new byte[]{};
        for (String piece : pieces) {
            if (piece == null) continue;
            byte[] tmp = Base642Bytes(piece);
            byte[] joinedArray = Arrays.copyOf(buff, buff.length + tmp.length);
            System.arraycopy(tmp, 0, joinedArray, buff.length, tmp.length);
            buff = joinedArray;
        }
        if (buff.length == 0) return "";
        return inflate(buff);
    }

    public int CSV2SQL(final ResultSet rs, final String SQLFileName, final String CSVfileName, final String header, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (SQLWriter writer = new SQLWriter(SQLFileName)) {
                writer.setFileHead(header);
                setExclusiveAndRemap(writer, excludes, remaps);
                return writer.writeAll2SQL(CSVfileName, rs);
            }
        });
    }

    public void AsyncPrintResult(final ResultSet rs, final String prefix, final int timeout) throws Exception {
        ArrayBlockingQueue<String> queue = new ArrayBlockingQueue<String>(1000);
        setCurrentResultSet(rs);
        Exception[] e = new Exception[1];
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    while (rs.next()) {
                        final String line = rs.getString(1);
                        queue.put(line == null ? "" : line);
                    }
                    rs.close();
                } catch (Exception e1) {
                    e[0] = e1;
                }
            }
        });
        t.setDaemon(true);
        t.start();
        ArrayList<String> messages = new ArrayList<>();
        String str;
        while (t.isAlive()) {
            while ((str = queue.poll(timeout, TimeUnit.MILLISECONDS)) != null) {
                messages.add(str);
                if (messages.size() >= console.getScreenHeight() * 3) break;
            }
            if (messages.size() > 0) {
                String[] msg = messages.toArray(new String[0]);
                messages.clear();
                console.println(prefix + String.join("\n" + prefix, msg));
            }
        }
        if (e[0] != null) throw e[0];
    }

    public LuaTable fetchResult(final ResultSet rs, final int rows) throws Exception {
        if (rs.getStatement().isClosed() || rs.isClosed()) throw CancelError;
        setCurrentResultSet(rs);
        return new LuaTable((Object[]) asyncCall(() -> {
            try (ResultSetHelperService helper = new ResultSetHelperService(rs)) {
                ResultSetHelperService.IS_TRIM = false;
                return (rows >= 0 && rows <= 10000) ? helper.fetchRows(rows) : helper.fetchRowsAsync(rows);
            }
        }));
    }

    public void closeWithoutWait(final Connection conn) {
        Thread t = new Thread(() -> {
            try {
                conn.close();
            } catch (Exception e) {
            }
        });
        t.setDaemon(true);
        t.start();
    }

    public LuaTable fetchCSV(final String CSVFileSource, final int rows) throws Exception {
        ArrayList<String[]> list = (ArrayList<String[]>) asyncCall(() -> {
            ArrayList<String[]> ary = new ArrayList();
            String[] line;
            int size = 0;
            try (CSVReader reader = new CSVReader(new FileReader(CSVFileSource))) {
                while ((line = reader.readNext()) != null) {
                    ++size;
                    if (rows > -1 && size > rows) break;
                    ary.add(line);
                }
            }
            return ary;
        });
        return new LuaTable(list.toArray());
    }

    public String inflate(byte[] data) throws Exception {
        ByteArrayInputStream bis = new ByteArrayInputStream(data);
        InflaterInputStream iis;
        try {
            iis = new InflaterInputStream(bis);
        } catch (Exception e1) {
            try {
                iis = new GZIPInputStream(bis);
            } catch (Exception e2) {
                throw e1;
            }
        }

        try (Closeable ignored = iis; ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
            UniversalDetector detector = new UniversalDetector(null);
            byte[] buffer = new byte[16384];
            int len;
            while ((len = iis.read(buffer)) > 0)
                bos.write(buffer, 0, len);
            buffer = bos.toByteArray();
            detector.handleData(buffer);
            detector.dataEnd();
            String charset = detector.getDetectedCharset();
            if (charset != null && !charset.equals("null")) {
                return new String(buffer, charset);
            } else
                return new String(buffer);
        }
    }

    public synchronized boolean setStatement(final CallableStatement p) throws Exception {
        try (Closeable ignored = console::setEvents) {
            this.stmt = p;
            console.setEvents(p == null ? null : q, new char[]{'q', 'Q'});
            if (p == null) return false;
            boolean result = p.execute();
            if (p.isClosed()) throw CancelError;
            return result;
        } catch (Exception e) {
            //e.printStackTrace();
            throw e;
        } finally {
            console.setEvents(null, null);
            this.stmt = null;
        }
    }

    public Object asyncCall(Callable<Object> c) throws Exception {
        try {
            this.sleeper = Console.threadPool.submit(c);
            console.setEvents(q, new char[]{'q', 'Q'});
            return sleeper.get();
        } catch (CancellationException | InterruptedException e) {
            throw CancelError;
        } catch (Exception e) {
            e = getRootCause(e);
            //e.printStackTrace();
            throw e;
        } finally {
            if (rs != null && !rs.isClosed()) rs.close();
            sleeper = null;
            rs = null;
            console.setEvents(null, null);
        }
    }

    public synchronized Object asyncCall(final Object o, final String func, final Object... args) throws Exception {
        return asyncCall(() -> {
            ClassAccess access = ClassAccess.access(LuaState.toClass(o));
            return access.invoke(o, func, args);
        });
    }

    public synchronized void sleep(int millSeconds) throws Exception {
        try (Closeable clo = console::setEvents) {
            runner.setSleep(millSeconds);
            sleeper = Console.threadPool.submit(runner);
            console.setEvents(q, new char[]{'q'});
            sleeper.get();
        } catch (Exception e) {
            throw CancelError;
        } finally {
            sleeper = null;
        }
    }

    /*
        public Commander newExtProcess(String cmd) {
            return new Commander(printer,cmd,console);
        }
    */
    private class KeyListner implements ActionListener {
        int key;

        public KeyListner(int k) {
            this.key = k;
        }

        @Override
        public void actionPerformed(ActionEvent e) {
            try {
                if (e != null) key = Character.codePointAt(e.getActionCommand(), 0);
                if (sleeper != null) {
                    sleeper.cancel(true);
                }
                if (console.isRunning() && stmt != null && !stmt.isClosed()) {
                    stmt.cancel();
                    stmt = null;
                }
                if (rs != null && !rs.isClosed()) {
                    rs.getStatement().close();
                    rs.close();
                }
            } catch (Exception err) {
                //getRootCause(err).printStackTrace();
            }
        }
    }

    private class Sleeper implements Runnable {
        private int timer = 0;

        public void setSleep(int t) {
            timer = t;
        }

        public void run() {
            try {
                synchronized (this) {
                    Thread.sleep(timer);
                }
            } catch (InterruptedException e) {

            }
        }
    }
}