package de.benibela.videlibri;

import android.*;
import android.R;
import android.app.Activity;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.util.Log;
import android.util.Pair;

import java.io.Serializable;
import java.util.*;

public class Bridge {
    public static class LibraryDetails {
        String homepageBase, homepageCatalogue;
        String prettyName;
        String id;
        String templateId;
        String variableNames[];
        String variableValues[];
    }

    public static class Account implements Serializable{
        String libId, name, pass, prettyName;
        boolean extend;
        int extendDays;
        boolean history;
        public boolean equals(Object o) {
            if (!(o instanceof Account)) return  false;
            Account a = (Account) o;
            return  (a.libId == libId && a.prettyName == prettyName);
        }
        String internalId(){
            return libId+"#"+name;
        }
        Library getLibrary(){ //warning slow
            Library[] libs = getLibraries();
            for (Library lib: libs)
                if (lib.id.equals(libId)) return lib;
            return null;
        }
    }

    static int currentPascalDate;
    public static class SimpleDate {
        private int year, month, day;
        public int pascalDate;
        SimpleDate (int year, int month, int day, int pascalDate){
            this.year = year;
            this.month = month;
            this.day = day;
            this.pascalDate = pascalDate;
        }
        Date getTime(){
            return new Date(year - 1900, month, day);
        }
    }

    public static class Book implements Serializable{

        public static class Pair implements Serializable{   //android.os.Pair is not serializable
            String first, second;
            Pair (String a, String b){
                first = a;
                second = b;
            }
        }


        Account account;
        String author = "";
        String title = "";
        SimpleDate issueDate; //might be null
        SimpleDate dueDate; //might be null
        boolean history;
        ArrayList<Pair> more = new ArrayList<Pair>();
        private int status;

        Bitmap image; //handled on Javasite only

        @Override
        public String toString() {
            return title;
        }

        int getStatusColor(){
            int c = Color.GREEN;
            if (this.history) c = -1;
            else if (dueDate != null && this.dueDate.pascalDate - currentPascalDate <= 3)
                c = Color.RED;
            else switch (getStatus()){
                case Normal: return Color.GREEN;
                case Problematic: return Color.YELLOW;
                case Ordered: return Color.CYAN;
                case Provided: return Color.MAGENTA;
                default: return Color.RED; //should not occur
            }
            return c;
        }

        enum StatusEnum { Unknown, Normal, Problematic, Ordered, Provided };

        StatusEnum getStatus() {
            switch (status) {
                case 1: return StatusEnum.Normal;
                case 2: return StatusEnum.Problematic;
                case 3: return StatusEnum.Ordered;
                case 4: return StatusEnum.Provided;
                default: return StatusEnum.Unknown;
            }
        }

        boolean isOrderable(){
            String orderable = getProperty("orderable");
            return (orderable != null && !"".equals(orderable) && !"0".equals(orderable) && !"false".equals(orderable));
        }
        boolean isCancelable(){
            String cancelable = getProperty("cancelable");;
            return cancelable == null || !"false".equals(cancelable);
        }

        //called from Videlibri midend
        void setProperty(String name, String value){
            more.add(new Pair(name, value));
        }

        String getProperty(String name){
            for (int i=more.size()-1;i>=0;i--)       //backward for simple overriding
                if (more.get(i).first.equals(name))
                    return more.get(i).second;
            return "";
        }

        boolean hasProperty(String name){
            for (int i=more.size()-1;i>=0;i--)
                if (more.get(i).first.equals(name))
                    return true;
            return false;
        }
    }

    public static class InternalError extends Exception {
        public InternalError() {}
        public InternalError(String msg) { super(msg); }
    }

    public static class PendingException{
        String accountPrettyNames, error, library, searchQuery, details, anonymousDetails;
    }

    public static class Options{
        boolean logging;
        int nearTime, refreshInterval;
        String roUserLibIds[];
    }

    public static class TemplateDetails{
        String variablesNames[];
        String variablesDescription[];
        String variablesDefault[];
    }

    static private native void VLInit(VideLibriContext videlibri);
    static public native String[] VLGetLibraries(); //id|pretty location|name|short name
    static public native LibraryDetails VLGetLibraryDetails(String id);
    static public native void VLSetLibraryDetails(String id, LibraryDetails details);
    static public native void VLInstallLibrary(String url);
    static public native String[] VLGetTemplates(); //array of ids
    static public native TemplateDetails VLGetTemplateDetails(String id);
    static public native Account[] VLGetAccounts();
    static public native void VLAddAccount(Account acc);
    static public native void VLChangeAccount(Account oldacc, Account newacc);
    static public native void VLDeleteAccount(Account acc);
    static public native Book[] VLGetBooks(Account acc, boolean history);
    static public native boolean VLUpdateAccount(Account acc, boolean autoUpdate, boolean forceExtend);
    static final int BOOK_OPERATION_RENEW = 1;
    static final int BOOK_OPERATION_CANCEL = 2;
    static public native void VLBookOperation(Book[] books, int operation);
    static public native PendingException[] VLTakePendingExceptions();

    static public native String[] VLGetNotifications();

    static public native void VLSearchConnect(SearcherAccess searcher, String libId);
    static public native void VLSearchStart(SearcherAccess searcher, Book query, int homeBranch, int searchBranch);
    static public native void VLSearchNextPage(SearcherAccess searcher);
    static public native void VLSearchDetails(SearcherAccess searcher, Book book);
    static public native void VLSearchOrder(SearcherAccess searcher, Book[] book);
    static public native void VLSearchOrderConfirmed(SearcherAccess searcher, Book[] book);
    static public native void VLSearchCompletePendingMessage(SearcherAccess searcher, int result);
    static public native void VLSearchEnd(SearcherAccess searcher);

    static public native void VLSetOptions(Options options);
    static public native Options VLGetOptions();

    static public native void VLFinalize();


    //SearcherAccess helper class like in Pascal-VideLibri
    //All methods run asynchronously in a Pascal Thread
    //All events are called in the same thread ()
    public static class SearcherAccess implements SearchResultDisplay{
        long nativePtr;

        final String libId;
        SearchConnector connector;
        SearchResultDisplay display;
        boolean waitingForDisplay;

        int totalResultCount;
        boolean nextPageAvailable;
        String[] homeBranches, searchBranches;

        SearcherAccess(SearchConnector connector, String libId){
            this.connector = connector;
            this.libId = libId;
            this.display = null;
            VLSearchConnect(this, libId);
        }
        public void setDisplay(SearchResultDisplay display){
            this.display = display;
            this.waitingForDisplay = false;
        }
        public void start(Book query, int homeBranch, int searchBranch){
            VLSearchStart(this, query, homeBranch, searchBranch);
        }
        public void nextPage(){
            VLSearchNextPage(this);
        }
        public void details(Book book){
            VLSearchDetails(this, book);
        }
        public void order(Book book){
            VLSearchOrder(this, new Book[]{book});
        }
        public void orderConfirmed(Book book){
            VLSearchOrderConfirmed(this, new Book[]{book});
        }
        public void completePendingMessage(int result){
            VLSearchCompletePendingMessage(this, result);
        }
        public void free(){
            display = null;
            connector = null;
            VLSearchEnd(this);
        }

        public void onConnected(String[] homeBranches, String[] searchBranches){ if (connector != null) connector.onConnected(homeBranches, searchBranches); }
        public void onSearchFirstPageComplete(Book[] books) { if (display != null) display.onSearchFirstPageComplete(books); }
        public void onSearchNextPageComplete(Book[] books) { if (display != null) display.onSearchNextPageComplete(books); }
        public void onSearchDetailsComplete(Book book) { if (display != null) display.onSearchDetailsComplete(book); }
        public void onOrderComplete(Book book) { if (display != null) display.onOrderComplete(book); }
        public void onOrderConfirm(Book book) { if (display != null) display.onOrderConfirm(book); }
        public void onTakePendingMessage(int kind, String caption, String[] options) { if (display != null) display.onTakePendingMessage(kind, caption, options); }
        public void onPendingMessageCompleted() { if (display != null) display.onPendingMessageCompleted(); }
        public void onException() { if (display != null) display.onException(); else if (connector != null) connector.onException();}
    }

    public static interface SearchConnector{
        void onConnected(String[] homeBranches, String[] searchBranches);
        void onException();
    }

    public static interface SearchResultDisplay extends SearchConnector{
        void onSearchFirstPageComplete(Book[] books);
        void onSearchNextPageComplete(Book[] books);
        void onSearchDetailsComplete(Book book);
        void onOrderComplete(Book book);
        void onOrderConfirm(Book book);
        void onTakePendingMessage(int kind, String caption, String[] options);
        void onPendingMessageCompleted();
    }

    static class Library{
        String id, fullStatePretty, locationPretty, namePretty, nameShort;
        void putInIntent(Intent intent){
            intent.putExtra("libName", namePretty);
            intent.putExtra("libShortName", nameShort);
            intent.putExtra("libId", id);
        }
    }
    static Library[] getLibraries(){
        String libs[] =  VLGetLibraries();
        ArrayList<Library> important = new ArrayList<Library>();
        Library[] result = new Library[libs.length];
        for (int i=0;i<libs.length;i++){
            result[i] = new Library();
            String[] temp = libs[i].split("\\|");
            result[i].id = temp[0];
            result[i].fullStatePretty = temp[1];
            result[i].locationPretty = temp[2];
            result[i].namePretty = temp[3];
            result[i].nameShort = temp[4];
            if (result[i].namePretty.contains("(Neu)")) important.add(result[i]);
        }
        Arrays.sort(result, new Comparator<Library>() {
            @Override
            public int compare(Library library, Library library2) {
                if (library.fullStatePretty.charAt(0) != library2.fullStatePretty.charAt(0)) {
                    if (library.fullStatePretty.charAt(0) == 'D') return -1;
                    else if (library2.fullStatePretty.charAt(0) == 'D') return 1;
                }
                int r = library.fullStatePretty.compareTo(library2.fullStatePretty);
                if (r != 0) return r;
                r = library.locationPretty.compareTo(library2.locationPretty);
                if (r != 0) return r;
                return library.namePretty.compareTo(library2.namePretty);
            }
        });
        if (important.size() > 0) {
            important.addAll(Arrays.asList(result));
            result = important.toArray(new Library[important.size()]);
        }
        return result;
    }

    //const libID: string; prettyName, aname, pass: string; extendType: TExtendType; extendDays:integer; history: boolean

    //mock functions

    /*static public Account[] VLGetAccounts(){
        return new Account[0];
    }
    static public void VLAddAccount(Account acc){

    }
    static public void VLChangeAccount(Account oldacc, Account newacc){

    }
    static public void VLDeleteAccount(Account acc){}*/
    //static public Book[] VLGetBooks(Account acc, boolean history){return  new Book[0];}
    //static public void VLUpdateAccount(Account acc){}


    //called from VideLibri

    public static interface VideLibriContext{
        String userPath();
    }


    static void allThreadsDone(){
        if (VideLibriApp.allThreadsDoneHandler == null) return;
        VideLibriApp.allThreadsDoneHandler.sendEmptyMessage(0);

    }

    static void installationDone(final int status){
        if (VideLibriApp.installationDoneHandler == null) return;
        VideLibriApp.installationDoneHandler.sendEmptyMessage(status);
    }

    //init

    static public void log(final String message){
        Log.i("VideLibri", message);
    }

    static boolean initialized = false;
    static public void initialize(VideLibriContext context){
        if (initialized) return;
        initialized = true;
        try
        {
            Log.i("Videlibri", "Trying to load liblclapp.so");
            System.loadLibrary("lclapp");
            VLInit(context);
        }
        catch(UnsatisfiedLinkError ule)
        {
            Log.e("Videlibri", "WARNING: Could not load liblclapp.so: " + ule.getMessage());
            ule.printStackTrace();
        }
    }
}