# Hướng dẫn TunnelDetour

[← README chính](README.md)

## TunnelDetour là gì

TunnelDetour là tiện ích macOS giúp một số dịch vụ do bạn chọn đi qua kết nối mạng
thông thường trong khi VPN vẫn được giữ nguyên. Ứng dụng không tự kết nối, ngắt hay
thay đổi cấu hình VPN.

## Lưu ý trước khi dùng

- Chỉ dùng trên máy và mạng bạn có quyền quản trị.
- Chỉ đưa ra ngoài VPN những đích mà chính sách của bạn cho phép.
- Bản Beta ký ad-hoc, chưa được Apple notarize và yêu cầu macOS 13 trở lên.
- Ứng dụng cần quyền quản trị để thêm/xóa route, resolver và cài helper giới hạn.

## Cài đặt

1. Tải `TunnelDetour.zip` cùng file `.sha256` từ GitHub Releases.
2. Có thể kiểm tra bằng `shasum -a 256 -c TunnelDetour.zip.sha256`.
3. Giải nén và kéo `TunnelDetour.app` vào Applications.
4. Trong Finder, Control-click hoặc nhấp chuột phải ứng dụng → **Open** → **Open**.

Không cần và không nên tắt Gatekeeper toàn hệ thống.

## Thiết lập lần đầu

1. Kết nối VPN theo cách bình thường.
2. Chọn nhóm dịch vụ cần đi trực tiếp; bỏ chọn những nhóm không cần thiết.
3. Thêm domain hoặc IPv4 tùy chỉnh, mỗi dòng một giá trị. Dạng `*.example.com` sẽ
   tự được lưu thành `example.com`, vốn đã áp dụng cho các subdomain.
4. Kiểm tra interface mạng thường và DNS public. Mặc định là `en0`, `8.8.8.8`,
   `1.1.1.1`; hãy sửa nếu máy bạn dùng giá trị khác.
5. **Private Check (optional)** để trống. Chỉ nhập hostname mạng riêng khi bạn có
   quyền sử dụng hostname đó để kiểm tra kết nối.
6. Bấm **Apply** và duyệt hộp thoại quyền quản trị của macOS.
7. Bấm **Verify** hoặc dùng ô kiểm tra site.

## Sử dụng hằng ngày

- Kết nối VPN trước, sau đó mở TunnelDetour và bấm Apply.
- Khi thêm/bớt dịch vụ, lưu rồi Apply lại.
- Không thêm cả dải mạng lớn nếu chỉ cần một domain hoặc IP.
- Có thể đổi Wi-Fi/gateway mà không cần Restore trước. TunnelDetour sẽ tạm trả DNS
  về đường mạng bình thường rồi tự áp lại route khi gateway mới ổn định.

Sau ba lần Apply thành công, ứng dụng có thể mời Sponsor một lần. **Maybe Later**
chỉ nhắc lại sau mười lần Apply thành công nữa; **Don't Show Again** tắt lời nhắc.
Ứng dụng không tự mở trình duyệt, không khóa tính năng và không gửi bộ đếm ra ngoài.

## Private Check

Đây là kiểm tra tùy chọn để chắc rằng một hostname mạng riêng vẫn phân giải được
sau khi áp dụng route. Nó không phải tên VPN và không cần thiết cho đa số người dùng.
Không chia sẻ hostname riêng trong issue, ảnh chụp hoặc log public.

## Khôi phục khi mạng lỗi

1. Sau khi đổi mạng, chờ vài giây để ứng dụng tự phục hồi.
2. Nếu vẫn lỗi, chọn **More → Restore Network**.
3. Ngắt rồi kết nối lại VPN bằng ứng dụng VPN của bạn và Apply lại.
4. Nếu helper không phản hồi, chọn **More → Remove Helper**, mở lại TunnelDetour và Apply.
5. Nếu vẫn lỗi, khởi động lại macOS và gửi issue đã xóa sạch thông tin riêng.

## Gỡ cài đặt

1. Chọn **Restore Network**.
2. Chọn **Remove Helper** và duyệt quyền quản trị.
3. Quit ứng dụng rồi xóa khỏi Applications.
4. Nếu muốn xóa cấu hình, dùng Finder → **Go to Folder** để mở Application Support
   trong Library của người dùng và xóa thư mục `TunnelDetour`.

## Tự build

Yêu cầu macOS 13+, Xcode command-line tools và Swift 5.9+.

```bash
swift test
./package_release.sh dist
```

App/ZIP/checksum nằm trong `dist`. Bản tự build ký ad-hoc và chưa notarize.
