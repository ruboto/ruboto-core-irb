package org.ruboto;

public class RubotoEditText extends android.widget.EditText {
	public RubotoEditText(android.content.Context context) {
		super(context);
	}

	public RubotoEditText(android.content.Context context, android.util.AttributeSet attrs) {
		super(context, attrs);
	}

	public RubotoEditText(android.content.Context context, android.util.AttributeSet attrs, int defStyle) {
		super(context, attrs, defStyle);
	}
	
    @Override 
    protected void onDraw(android.graphics.Canvas canvas) {
    	((RubotoActivity) getContext()).onDraw(this, canvas);
    	super.onDraw(canvas);
    }
	
    @Override 
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
    	((RubotoActivity) getContext()).onSizeChanged(this, w, h, oldw, oldh);
    	super.onSizeChanged(w, h, oldw, oldh);
    }
}
