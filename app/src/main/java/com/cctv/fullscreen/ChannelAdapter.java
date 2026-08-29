package com.cctv.fullscreen;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.List;

/** 主页频道卡片：上行小字 label（CCTV-5+），下行大字 title（体育赛事）。 */
public final class ChannelAdapter extends RecyclerView.Adapter<ChannelAdapter.Holder> {

    public interface OnChannelClick {
        void onChannelClick(Channel channel);
    }

    private final List<Channel> channels;
    private final String lastChannelId;
    private final OnChannelClick listener;

    public ChannelAdapter(List<Channel> channels, String lastChannelId, OnChannelClick listener) {
        this.channels = channels;
        this.lastChannelId = lastChannelId;
        this.listener = listener;
    }

    @NonNull
    @Override
    public Holder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_channel, parent, false);
        return new Holder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull Holder holder, int position) {
        final Channel channel = channels.get(position);
        holder.label.setText(channel.label);
        holder.title.setText(channel.title);
        holder.itemView.setSelected(channel.id.equals(lastChannelId));
        holder.itemView.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                listener.onChannelClick(channel);
            }
        });
    }

    @Override
    public int getItemCount() {
        return channels.size();
    }

    static final class Holder extends RecyclerView.ViewHolder {
        final TextView label;
        final TextView title;

        Holder(View itemView) {
            super(itemView);
            label = itemView.findViewById(R.id.channel_label);
            title = itemView.findViewById(R.id.channel_title);
        }
    }
}
