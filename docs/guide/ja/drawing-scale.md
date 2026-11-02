<!-- keywords: 縮尺, 校正, キャリブレーション, 図面, 建築, メートル法, 土木, 比率, scale, calibrate, calibration, drawing, architectural, metric, engineering, ratio -->
<!-- source: 93a3eb4583cc -->

# 図面の縮尺を設定する

図面から実際の寸法を測定するには、VectorPDF が図面の縮尺を認識している必要があります。⇧⌘M を押して Measurement ツールバーを表示し、縮尺ボタンをクリックして Drawing Scale Calibration を開きます。

## 標準の縮尺を使用する

1. Standard Drawing Scales で、図面の種類を選択します:
   - **Metric (ISO):** 1:1 から 1:1000 まで。
   - **Architectural (US):** 1/4" = 1'-0" など。
   - **Civil Engineering (US).**
2. 縮尺を選択します。
3. Area Takeoff で、面積の単位を選択します。
4. Apply Scale をクリックします。

縮尺はすべてのページに適用され、[保存](save.md)すると PDF に記録されます。

## 既知の長さから校正する

信頼できる寸法や縮尺バーが図面にある場合:

1. **Calibrate by Measuring Known Line** をクリックします。
2. 図面上で線の両端をクリックします。
3. 線の実際の長さを入力し、単位を選択します: フィートとインチ、フィート (10 進数)、インチ、ミリメートル、センチメートル、メートル。
4. Apply Scale をクリックします。

クリック時のわずかなずれは距離が長いほど影響が小さくなるため、できるだけ長い既知の線を使用してください。
