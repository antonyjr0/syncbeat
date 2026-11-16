/* SPDX-License-Identifier: AGPL-3.0-or-later */
package com.antonyjr0.syncbeat.zepp;

import static org.junit.Assert.*;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.View;
import android.widget.*;
import java.io.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class UiTest {
  @Test
  public void initialScreenAndScrollRenderWithoutSecrets() throws Exception {
    try (org.robolectric.android.controller.ActivityController<PrototypeActivity> controller =
        Robolectric.buildActivity(PrototypeActivity.class).setup()) {
      PrototypeActivity activity = controller.get();
      ScrollView scroll =
          (ScrollView)
              ((android.view.ViewGroup) activity.findViewById(android.R.id.content)).getChildAt(0);
      // Native Android Canvas pixels at two phone viewport sizes, not an HTML recreation.
      for (int width : new int[] {320, 390}) {
        scroll.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(740, View.MeasureSpec.EXACTLY));
        scroll.layout(0, 0, width, 740);
        for (int page = 0; page < 2; page++) {
          org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle();
          Bitmap bitmap = Bitmap.createBitmap(width, 740, Bitmap.Config.ARGB_8888);
          Canvas canvas = new Canvas(bitmap);
          canvas.drawColor(android.graphics.Color.WHITE);
          canvas.translate(0, -page * 620);
          scroll.getChildAt(0).draw(canvas);
          File output = new File("build/ui-preview/zepp-" + width + "-" + page + ".png");
          output.getParentFile().mkdirs();
          try (FileOutputStream stream = new FileOutputStream(output)) {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
          }
          bitmap.recycle();
        }
      }
      LinearLayout content = (LinearLayout) scroll.getChildAt(0);
      boolean sawUpload = false;
      for (int i = 0; i < content.getChildCount(); i++)
        if (content.getChildAt(i) instanceof Button) {
          Button b = (Button) content.getChildAt(i);
          if (b.getText().toString().equals("Invia MP3 al lettore nativo")) {
            sawUpload = true;
            assertFalse(b.isEnabled());
          }
        }
      assertTrue(sawUpload);
    }
  }

  @Test
  public void noDeviceCannotConnectAndKeyEntryIsProtected() throws Exception {
    try (org.robolectric.android.controller.ActivityController<PrototypeActivity> controller =
        Robolectric.buildActivity(PrototypeActivity.class).setup()) {
      PrototypeActivity activity = controller.get();
      ScrollView scroll =
          (ScrollView)
              ((android.view.ViewGroup) activity.findViewById(android.R.id.content)).getChildAt(0);
      LinearLayout content = (LinearLayout) scroll.getChildAt(0);
      Button verify = null;
      EditText secret = null;
      for (int i = 0; i < content.getChildCount(); i++) {
        View v = content.getChildAt(i);
        if (v instanceof Button
            && ((Button) v).getText().toString().startsWith("Verifica collegamento"))
          verify = (Button) v;
        if (v instanceof EditText && ((EditText) v).getHint().toString().startsWith("Chiave"))
          secret = (EditText) v;
      }
      assertNotNull(verify);
      assertNotNull(secret);
      verify.performClick();
      boolean sawError = false;
      for (int i = 0; i < content.getChildCount(); i++)
        if (content.getChildAt(i) instanceof TextView
            && ((TextView) content.getChildAt(i))
                .getText()
                .toString()
                .contains("Prima scegli esplicitamente")) sawError = true;
      assertTrue(sawError);
      assertFalse(secret.isSaveEnabled());
      secret.requestFocus();
      assertTrue(
          (activity.getWindow().getAttributes().flags
                  & android.view.WindowManager.LayoutParams.FLAG_SECURE)
              != 0);
      assertTrue(
          secret.getTransformationMethod()
              instanceof android.text.method.PasswordTransformationMethod);
      controller.pause().stop();
      assertEquals("", secret.getText().toString());
    }
  }
}
