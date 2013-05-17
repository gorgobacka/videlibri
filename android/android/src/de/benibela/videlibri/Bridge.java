package de.benibela.videlibri;

import android.*;
import android.R;
import android.graphics.Color;
import android.util.Log;

import java.io.Serializable;
import java.util.Calendar;
import java.util.GregorianCalendar;
import java.util.Map;
import java.util.TreeMap;

public class Bridge {
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
            return libId+"_"+name;
        }
    }

    public static class Book implements Serializable{
        Account account;
        String author = "";
        String title = "";
        String dueDatePretty = "";
        GregorianCalendar issueDate;
        GregorianCalendar dueDate;
        boolean history;
        Map<String, String> more = new TreeMap<String, String>();

        @Override
        public String toString() {
            return title;
        }

        int getStatusColor(){
            if (dueDate == null) return -1;
            int c = Color.GREEN;
            if (this.history) c = -1;
            else if (this.dueDate.getTimeInMillis() - Calendar.getInstance().getTimeInMillis() < 1000 * 60 * 60 * 24 * 3) c = Color.RED;
            else if ("critical".equals(this.more.get("statusId"))) c = Color.YELLOW;
            else c = Color.GREEN;
            return c;
        }

        //called from Videlibri midend
        void setProperty(String name, String value){
            more.put(name, value);
        }
    }

    public static class InternalError extends Exception {
        public InternalError() {}
        public InternalError(String msg) { super(msg); }
    }

    public static class PendingException{
        String accountPrettyNames, error, details;
    }

    static public native void VLInit(VideLibri videlibri);
    static public native String[] VLGetLibraries(); //id|pretty location|name|short name
    static public native Account[] VLGetAccounts();
    static public native void VLAddAccount(Account acc);
  //public native void VLChangeAccount(Account oldacc, Account newacc);
  //public native void VLDeleteAccount(Account acc);
    static public native Book[] VLGetBooks(Account acc, boolean history);
    static public native void VLUpdateAccount(Account acc, boolean autoUpdate, boolean forceExtend);
    static public native PendingException[] VLTakePendingExceptions();


    static public native void VLSearchStart(SearcherAccess searcher, Book query);
    static public native void VLSearchNextPage(SearcherAccess searcher);
    static public native void VLSearchDetails(SearcherAccess searcher, Book book);
    static public native void VLSearchEnd(SearcherAccess searcher);

    static public native void VLFinalize();



    public static class SearcherAccess implements SearchResultDisplay{
        long nativePtr;
        final SearchResultDisplay display;

        int totalResultCount;
        boolean nextPageAvailable;

        SearcherAccess(SearchResultDisplay display, Book query){
            this.display = display;
            VLSearchStart(this, query);
        }
        public void nextPage(){
            VLSearchNextPage(this);
        }
        public void details(Book book){
            VLSearchDetails(this, book);
        }
        public void free(){
            VLSearchEnd(this);
        }

        public void onSearchFirstPageComplete(Book[] books) { display.onSearchFirstPageComplete(books); }
        public void onSearchNextPageComplete(Book[] books) { display.onSearchNextPageComplete(books); }
        public void onSearchDetailsComplete(Book book) { display.onSearchDetailsComplete(book); }
        public void onException() { display.onException(); }
    }


    public static interface SearchResultDisplay{
        void onSearchFirstPageComplete(Book[] books);
        void onSearchNextPageComplete(Book[] books);
        void onSearchDetailsComplete(Book book);
        void onException();
    }

    //const libID: string; prettyName, aname, pass: string; extendType: TExtendType; extendDays:integer; history: boolean 

    //mock functions

    /*static public Account[] VLGetAccounts(){
        return new Account[0];
    }
    static public void VLAddAccount(Account acc){

    } */
    static public void VLChangeAccount(Account oldacc, Account newacc){

    }
    static public void VLDeleteAccount(Account acc){}
    //static public Book[] VLGetBooks(Account acc, boolean history){return  new Book[0];}
    //static public void VLUpdateAccount(Account acc){}


    static public void log(final String message){
        VideLibri.instance.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Log.i("VideLibri", message);
            }
        });

    }


    static
    {
        try //from LCLActivity
        {
            Log.i("videlibri", "Trying to load liblclapp.so");
            System.loadLibrary("lclapp");
        }
        catch(UnsatisfiedLinkError ule)
        {
            Log.e("videlibri", "WARNING: Could not load liblclapp.so");
            ule.printStackTrace();
        }
    }
}