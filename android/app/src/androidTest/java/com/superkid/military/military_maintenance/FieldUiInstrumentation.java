package com.superkid.military.military_maintenance;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import android.content.Intent;
import android.graphics.Bitmap;
import android.view.accessibility.AccessibilityNodeInfo;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.List;

/** UI-only test runner. Uses Android accessibility actions, including on release APKs. */
public final class FieldUiInstrumentation extends Instrumentation {
    private String plan;
    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        plan = args == null ? "[]" : args.getString("plan", "[]");
        start();
    }
    private List<AccessibilityNodeInfo> nodes() {
        List<AccessibilityNodeInfo> result = new ArrayList<>();
        collect(getUiAutomation().getRootInActiveWindow(), result);
        return result;
    }
    private void collect(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> result) {
        if (node == null) return;
        result.add(node);
        for (int i=0;i<node.getChildCount();i++) collect(node.getChild(i),result);
    }
    private String label(AccessibilityNodeInfo node) {
        return String.valueOf(node.getText()) + "\n" + String.valueOf(node.getContentDescription());
    }
    private String labels() {
        StringBuilder text = new StringBuilder();
        for (AccessibilityNodeInfo node:nodes()) {
            if (getTargetContext().getPackageName().contentEquals(
                    node.getPackageName() == null ? "" : node.getPackageName()))
                text.append(label(node)).append("\n");
        }
        return text.toString();
    }
    private boolean matches(CharSequence value, String text) {
        if(value == null) return false;
        for(String line:value.toString().split("\n"))
            if(text.equals(line)) return true;
        return false;
    }
    private AccessibilityNodeInfo find(String text) throws Exception {
        for (int attempt=0;attempt<60;attempt++) {
            for (AccessibilityNodeInfo node:nodes()) {
                if (!node.isVisibleToUser() || !node.isEnabled()) continue;
                if (matches(node.getText(), text) || matches(node.getContentDescription(), text))
                    return node;
            }
            Thread.sleep(200);
        }
        throw new IllegalStateException("missing_button:"+text);
    }
    private void click(String text) throws Exception {
        AccessibilityNodeInfo node=find(text);
        while(node!=null) {
            if(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return;
            node=node.getParent();
        }
        throw new IllegalStateException("not_clickable:"+text);
    }
    @Override public void onStart() {
        new Thread(() -> {
            Bundle result=new Bundle();
            int step=0;
            try {
                Intent intent=new Intent();
                intent.setClassName(getTargetContext().getPackageName(),
                    getTargetContext().getPackageName()+".MainActivity");
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getTargetContext().startActivity(intent);
                Thread.sleep(1200);
                JSONArray steps=new JSONArray(plan);
                if(steps.length()>80) throw new IllegalArgumentException("plan_limit");
                for(;step<steps.length();step++) {
                    JSONObject item=steps.getJSONObject(step);
                    String action=item.getString("action");
                    if(action.equals("click")) click(item.getString("label"));
                    else if(action.equals("wait")) {
                        String text=item.getString("text");
                        boolean found=false;
                        for(int attempt=0;attempt<60;attempt++) {
                            if(labels().contains(text)) {found=true;break;}
                            Thread.sleep(250);
                        }
                        if(!found) throw new IllegalStateException("missing_text:"+text);
                    } else if(action.equals("scroll")) {
                        int direction = item.optBoolean("forward", true)
                            ? AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                            : AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD;
                        List<AccessibilityNodeInfo> current = nodes();
                        boolean scrolled = false;
                        for (int index = current.size() - 1; index >= 0; index--) {
                            AccessibilityNodeInfo node = current.get(index);
                            if (node.isVisibleToUser() && node.isScrollable() && node.performAction(direction)) {
                                scrolled = true;
                                break;
                            }
                        }
                        if (!scrolled) throw new IllegalStateException("cannot_scroll");
                    } else if(action.equals("edit")) {
                        List<AccessibilityNodeInfo> inputs=new ArrayList<>();
                        for(AccessibilityNodeInfo n:nodes())
                            if("android.widget.EditText".contentEquals(n.getClassName())) inputs.add(n);
                        int index=item.optInt("index",-1);
                        if(index<0) index=inputs.size()-1;
                        Bundle value=new Bundle();
                        value.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            item.getString("text"));
                        if(index<0 || index>=inputs.size() ||
                            !inputs.get(index).performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,value))
                            throw new IllegalStateException("cannot_edit");
                    } else if(action.equals("screenshot")) {
                        String name=item.getString("name");
                        if(!name.matches("[a-z0-9_-]{1,60}")) throw new IllegalArgumentException("name");
                        Bitmap bitmap=getUiAutomation().takeScreenshot();
                        if(bitmap==null) throw new IllegalStateException("screenshot");
                        File folder=new File(getTargetContext().getExternalFilesDir(null),"qa");
                        if(!folder.isDirectory() && !folder.mkdirs())
                            throw new IllegalStateException("screenshot_directory");
                        try(FileOutputStream output=new FileOutputStream(
                            new File(folder,name+".png"))) {
                            bitmap.compress(Bitmap.CompressFormat.PNG,100,output);
                        }
                        bitmap.recycle();
                    } else if(action.equals("sleep")) Thread.sleep(Math.min(item.getInt("ms"),10000));
                    else throw new IllegalArgumentException("unknown_action");
                    Thread.sleep(350);
                }
                result.putString("status","passed");
                result.putString("screen",labels());
                result.putInt("completedSteps",step);
                finish(Activity.RESULT_OK,result);
            } catch(Throwable error) {
                result.putString("status","failed");
                result.putString("error",error.getClass().getSimpleName()+":"+error.getMessage());
                result.putString("screen",labels());
                result.putInt("completedSteps",step);
                finish(Activity.RESULT_CANCELED,result);
            }
        }).start();
    }
}
