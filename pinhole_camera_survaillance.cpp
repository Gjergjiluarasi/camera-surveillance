#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>

namespace {

constexpr int model_size = 640;
constexpr float confidence_threshold = 0.25F;
constexpr char window_name[] = "Pinhole Camera - YOLO26n";

struct LetterboxTransform {
    float scale;
    int left;
    int top;
};

LetterboxTransform letterbox(const cv::Mat& frame, cv::Mat& input) {
    const float scale = std::min(
        static_cast<float>(model_size) / frame.cols,
        static_cast<float>(model_size) / frame.rows);
    const int resized_width = static_cast<int>(std::round(frame.cols * scale));
    const int resized_height = static_cast<int>(std::round(frame.rows * scale));
    const int left = (model_size - resized_width) / 2;
    const int top = (model_size - resized_height) / 2;

    cv::Mat resized;
    cv::resize(frame, resized, cv::Size(resized_width, resized_height));
    cv::copyMakeBorder(
        resized, input, top, model_size - resized_height - top,
        left, model_size - resized_width - left, cv::BORDER_CONSTANT,
        cv::Scalar(114, 114, 114));
    return {scale, left, top};
}

void detect_and_draw(cv::dnn::Net& network, cv::Mat& frame) {
    cv::Mat model_input;
    const LetterboxTransform transform = letterbox(frame, model_input);
    cv::Mat blob = cv::dnn::blobFromImage(
        model_input, 1.0 / 255.0, cv::Size(model_size, model_size),
        cv::Scalar(), true, false, CV_32F);
    network.setInput(blob);

    cv::Mat output;
    network.forward(output);
    if (output.type() != CV_32F || output.total() % 6 != 0) {
        throw std::runtime_error(
            "Unexpected YOLO26 output; expected float detections with 6 values per box.");
    }

    cv::Mat detections;
    if (output.dims >= 2 && output.size[output.dims - 2] == 6) {
        detections = output.reshape(1, 6).t();
    } else {
        detections = output.reshape(1, static_cast<int>(output.total() / 6));
    }

    for (int row = 0; row < detections.rows; ++row) {
        const float* detection = detections.ptr<float>(row);
        const float confidence = detection[4];
        if (confidence < confidence_threshold) {
            continue;
        }

        const int x1 = static_cast<int>(std::round((detection[0] - transform.left) / transform.scale));
        const int y1 = static_cast<int>(std::round((detection[1] - transform.top) / transform.scale));
        const int x2 = static_cast<int>(std::round((detection[2] - transform.left) / transform.scale));
        const int y2 = static_cast<int>(std::round((detection[3] - transform.top) / transform.scale));
        const cv::Rect box(
            cv::Point(std::clamp(x1, 0, frame.cols - 1), std::clamp(y1, 0, frame.rows - 1)),
            cv::Point(std::clamp(x2, 0, frame.cols - 1), std::clamp(y2, 0, frame.rows - 1)));
        if (box.width <= 0 || box.height <= 0) {
            continue;
        }

        cv::rectangle(frame, box, cv::Scalar(40, 220, 40), 2);
        const std::string label = "class " + std::to_string(static_cast<int>(detection[5])) +
                                  " " + cv::format("%.2f", confidence);
        int baseline = 0;
        const cv::Size label_size = cv::getTextSize(
            label, cv::FONT_HERSHEY_SIMPLEX, 0.5, 1, &baseline);
        const int label_y = std::max(box.y, label_size.height + 4);
        cv::rectangle(frame,
                      cv::Point(box.x, label_y - label_size.height - 4),
                      cv::Point(box.x + label_size.width, label_y + baseline),
                      cv::Scalar(40, 220, 40), cv::FILLED);
        cv::putText(frame, label, cv::Point(box.x, label_y),
                    cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 0), 1);
    }
}

bool is_quit_key(int key) {
    return key == 27 || key == 'q' || key == 'Q';
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 5) {
        std::cerr << "Usage: " << argv[0]
                  << " --model yolo26n.onnx (--camera INDEX | --video FILE)\n";
        return 2;
    }

    std::string model_path;
    std::string video_path;
    int camera_index = -1;
    try {
        for (int argument = 1; argument < argc; ++argument) {
            const std::string option = argv[argument];
            if ((option == "--model" || option == "--video" || option == "--camera") &&
                argument + 1 < argc) {
                const std::string value = argv[++argument];
                if (option == "--model") {
                    model_path = value;
                } else if (option == "--video") {
                    video_path = value;
                } else {
                    std::size_t parsed_characters = 0;
                    camera_index = std::stoi(value, &parsed_characters);
                    if (parsed_characters != value.size() || camera_index < 0) {
                        throw std::invalid_argument("camera index must be non-negative");
                    }
                }
            } else {
                throw std::invalid_argument("unknown option or missing option value: " + option);
            }
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\nUsage: " << argv[0]
                  << " --model yolo26n.onnx (--camera INDEX | --video FILE)\n";
        return 2;
    }

    if (model_path.empty() || ((camera_index >= 0) == !video_path.empty())) {
        std::cerr << "Provide --model and exactly one of --camera or --video.\n";
        return 2;
    }

    try {
        cv::dnn::Net network = cv::dnn::readNetFromONNX(model_path);
        if (network.empty()) {
            std::cerr << "Could not load model: " << model_path << "\n";
            return 1;
        }
        network.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        network.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);

        cv::VideoCapture input;
        const bool is_video_file = !video_path.empty();
        const bool opened = is_video_file
                                ? input.open(video_path, cv::CAP_FFMPEG)
                                : input.open(camera_index, cv::CAP_V4L2);
        if (!opened) {
            std::cerr << (is_video_file ? "Could not open video file: " : "Could not open camera ")
                      << (is_video_file ? video_path : std::to_string(camera_index)) << "\n";
            return 1;
        }
        if (!is_video_file) {
            input.set(cv::CAP_PROP_BUFFERSIZE, 1);
        }

        double frame_rate = input.get(cv::CAP_PROP_FPS);
        if (!std::isfinite(frame_rate) || frame_rate <= 0.0) {
            frame_rate = 30.0;
        }
        const auto frame_interval = std::chrono::duration<double>(1.0 / frame_rate);

        cv::namedWindow(window_name, cv::WINDOW_AUTOSIZE);
        cv::Mat frame;
        while (true) {
            const auto frame_started = std::chrono::steady_clock::now();
            if (!input.read(frame) || frame.empty()) {
                if (!is_video_file) {
                    std::cerr << "Failed to read a frame from camera " << camera_index << ".\n";
                    input.release();
                    cv::destroyAllWindows();
                    return 1;
                }
                break;
            }

            detect_and_draw(network, frame);
            cv::imshow(window_name, frame);

            int wait_milliseconds = 1;
            if (is_video_file) {
                const auto elapsed = std::chrono::steady_clock::now() - frame_started;
                const auto remaining = frame_interval - elapsed;
                if (remaining > std::chrono::steady_clock::duration::zero()) {
                    wait_milliseconds = std::max(
                        1, static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                                remaining).count()));
                }
            }
            if (is_quit_key(cv::waitKey(wait_milliseconds))) {
                break;
            }
        }

        input.release();
        cv::destroyAllWindows();
        return 0;
    } catch (const cv::Exception& error) {
        std::cerr << "OpenCV error: " << error.what() << "\n";
        return 1;
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << "\n";
        return 1;
    }
}