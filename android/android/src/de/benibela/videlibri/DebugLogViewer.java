package de.benibela.videlibri;

import android.os.Bundle;
import android.util.Xml;
import android.widget.ListView;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class DebugLogViewer extends VideLibriBaseActivity {
    ArrayList<BookDetails.Details> details;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);    //To change body of overridden methods use File | Settings | File Templates.
        setContentView(R.layout.bookdetails_withactionbar);
        ListView lv = (ListView) findViewById(R.id.bookdetailsview);

        details = new ArrayList<BookDetails.Details>();

        Bridge.Options options = Bridge.VLGetOptions();
        if (!options.logging)
            details.add(new BookDetails.Details("", tr(R.string.debuglog_disabled)));

        try {
            //http://stackoverflow.com/questions/12692103/read-logcat-programmatically-within-application
            Process process = Runtime.getRuntime().exec("logcat -d");
            BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(process.getInputStream()));

            String line = "";
            Pattern pattern = Pattern.compile("([a-zA-Z]+/VideLibri.+?:)( *[-0-9:T ]+[(].*?[)] *:)?(.*)");
            BookDetails.Details lastDetails = null;
            while ((line = bufferedReader.readLine()) != null) {
                Matcher m = pattern.matcher(line);
                if (!m.matches()) {
                    details.add(new BookDetails.Details("", line));
                    lastDetails = null;
                } else if (lastDetails != null && (m.group(2) == null || m.group(2).isEmpty()))  {
                    lastDetails.data += lastDetails.data + "\n" + m.group(3);
                } else {
                    lastDetails = new BookDetails.Details(m.group(1) + m.group(2), m.group(3));
                    details.add(lastDetails);
                }
            }

        }
        catch (IOException e) {}

        lv.setAdapter(new BookDetails.BookDetailsAdapter(this, details, new Bridge.Book()));
    }
}
