#![no_main]

// fastqr_fuzz — drive fast_qr's full QR encoding pipeline over arbitrary input.
//
// The first input byte selects the error-correction level; the rest is the QR
// content. A successful build exercises encoding, error correction,
// placement, data masking and scoring; the Unicode + SVG conversions then walk
// the finished matrix. Content too large for any version returns Err, which is
// expected behavior (not a crash) and is ignored.

use fast_qr::convert::{svg::SvgBuilder, Builder, Shape};
use fast_qr::qr::QRBuilder;
use fast_qr::ECL;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.is_empty() {
        return;
    }
    let ecl = match data[0] & 0b11 {
        0 => ECL::L,
        1 => ECL::M,
        2 => ECL::Q,
        _ => ECL::H,
    };
    let content = &data[1..];
    if let Ok(qrcode) = QRBuilder::new(content).ecl(ecl).build() {
        let _ = qrcode.to_str();
        let _ = SvgBuilder::default()
            .shape(Shape::RoundedSquare)
            .to_str(&qrcode);
    }
});
