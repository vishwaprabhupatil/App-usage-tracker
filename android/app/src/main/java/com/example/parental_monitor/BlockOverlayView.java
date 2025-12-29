package com.example.parental_monitor;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Full-screen overlay view shown when a blocked app is detected.
 */
public class BlockOverlayView extends LinearLayout {

    public interface OnGoHomeListener {
        void onGoHome();
    }

    public BlockOverlayView(Context context, String packageName, OnGoHomeListener listener) {
        super(context);
        init(context, packageName, listener);
    }

    private void init(Context context, String packageName, OnGoHomeListener listener) {
        setOrientation(VERTICAL);
        setGravity(Gravity.CENTER);

        // Create gradient background (dark red to black)
        GradientDrawable gradient = new GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                new int[] { Color.parseColor("#B71C1C"), Color.BLACK });
        setBackground(gradient);

        // Padding
        int padding = dpToPx(context, 32);
        setPadding(padding, padding, padding, padding);

        // Block icon container (circular background)
        LinearLayout iconContainer = new LinearLayout(context);
        iconContainer.setOrientation(VERTICAL);
        iconContainer.setGravity(Gravity.CENTER);
        GradientDrawable circleBackground = new GradientDrawable();
        circleBackground.setShape(GradientDrawable.OVAL);
        circleBackground.setColor(Color.parseColor("#33FFFFFF"));
        iconContainer.setBackground(circleBackground);
        int iconContainerSize = dpToPx(context, 144);
        LayoutParams iconContainerParams = new LayoutParams(iconContainerSize, iconContainerSize);
        iconContainer.setLayoutParams(iconContainerParams);

        // Block icon
        ImageView blockIcon = new ImageView(context);
        blockIcon.setImageResource(android.R.drawable.ic_delete);
        blockIcon.setColorFilter(Color.WHITE);
        int iconSize = dpToPx(context, 80);
        LayoutParams iconParams = new LayoutParams(iconSize, iconSize);
        blockIcon.setLayoutParams(iconParams);
        iconContainer.addView(blockIcon);

        addView(iconContainer);

        // Spacer
        View spacer1 = new View(context);
        spacer1.setLayoutParams(new LayoutParams(LayoutParams.MATCH_PARENT, dpToPx(context, 40)));
        addView(spacer1);

        // Title
        TextView title = new TextView(context);
        title.setText("App Blocked");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 32);
        title.setGravity(Gravity.CENTER);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        addView(title);

        // Spacer
        View spacer2 = new View(context);
        spacer2.setLayoutParams(new LayoutParams(LayoutParams.MATCH_PARENT, dpToPx(context, 16)));
        addView(spacer2);

        // Subtitle
        TextView subtitle = new TextView(context);
        subtitle.setText("This app has been blocked by your parent");
        subtitle.setTextColor(Color.parseColor("#CCFFFFFF"));
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        subtitle.setGravity(Gravity.CENTER);
        LayoutParams subtitleParams = new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT);
        subtitleParams.setMargins(dpToPx(context, 48), 0, dpToPx(context, 48), 0);
        subtitle.setLayoutParams(subtitleParams);
        addView(subtitle);

        // Spacer
        View spacer3 = new View(context);
        spacer3.setLayoutParams(new LayoutParams(LayoutParams.MATCH_PARENT, dpToPx(context, 48)));
        addView(spacer3);

        // Info text
        TextView infoText = new TextView(context);
        infoText.setText("Ask your parent to unblock this app if you need to use it.");
        infoText.setTextColor(Color.parseColor("#99FFFFFF"));
        infoText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        infoText.setGravity(Gravity.CENTER);
        LayoutParams infoParams = new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT);
        infoParams.setMargins(dpToPx(context, 48), 0, dpToPx(context, 48), 0);
        infoText.setLayoutParams(infoParams);
        addView(infoText);

        // Spacer
        View spacer4 = new View(context);
        spacer4.setLayoutParams(new LayoutParams(LayoutParams.MATCH_PARENT, dpToPx(context, 48)));
        addView(spacer4);

        // Go Home button
        Button homeButton = new Button(context);
        homeButton.setText("Go to Home Screen");
        homeButton.setTextColor(Color.parseColor("#B71C1C"));
        homeButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        homeButton.setAllCaps(false);

        // Button background
        GradientDrawable buttonBackground = new GradientDrawable();
        buttonBackground.setColor(Color.WHITE);
        buttonBackground.setCornerRadius(dpToPx(context, 30));
        homeButton.setBackground(buttonBackground);

        LayoutParams buttonParams = new LayoutParams(LayoutParams.WRAP_CONTENT, dpToPx(context, 56));
        buttonParams.gravity = Gravity.CENTER;
        homeButton.setLayoutParams(buttonParams);
        homeButton.setPadding(dpToPx(context, 32), 0, dpToPx(context, 32), 0);

        homeButton.setOnClickListener(v -> {
            if (listener != null) {
                listener.onGoHome();
            }
        });

        addView(homeButton);
    }

    private int dpToPx(Context context, int dp) {
        float density = context.getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }
}
