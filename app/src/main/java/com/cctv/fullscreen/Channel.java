package com.cctv.fullscreen;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** 频道模型。label = "CCTV-5+"，title = "体育赛事"，卡片分两行显示。 */
public final class Channel {

    public final String id;
    public final int number;
    public final String label;
    public final String title;
    public final String name;
    public final String webUrl;

    public Channel(String id, int number, String label, String title, String name, String webUrl) {
        this.id = id;
        this.number = number;
        this.label = label;
        this.title = title;
        this.name = name;
        this.webUrl = webUrl;
    }

    public static Channel fromJson(JSONObject o) {
        String name = o.optString("name", "");
        String label = o.optString("label", "");
        String title = o.optString("title", "");
        // 兼容旧数据：没有 label/title 时从 name 拆
        if (label.isEmpty() || title.isEmpty()) {
            int sp = name.indexOf(' ');
            if (sp > 0) {
                if (label.isEmpty()) label = name.substring(0, sp);
                if (title.isEmpty()) title = name.substring(sp + 1);
            } else if (label.isEmpty()) {
                label = name;
            }
        }
        return new Channel(
                o.optString("id", ""),
                o.optInt("number", 0),
                label,
                title,
                name,
                o.optString("webUrl", ""));
    }

    public static List<Channel> parseCatalog(String raw) throws JSONException {
        JSONObject root = new JSONObject(raw);
        JSONArray array = root.optJSONArray("channels");
        List<Channel> out = new ArrayList<Channel>();
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONArray(i) == null ? array.optJSONObject(i) : null;
                if (item == null || !item.optBoolean("enabled", true)) {
                    continue;
                }
                out.add(fromJson(item));
            }
        }
        Collections.sort(out, new Comparator<Channel>() {
            @Override
            public int compare(Channel a, Channel b) {
                return a.number - b.number;
            }
        });
        return out;
    }
}
