#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>

#include <opencv2/opencv.hpp>

int main(int argc, char* argv[]) {
    if (argc > 2) {
        std::cerr << "Usage: " << argv[0] << " [camera-index]\n";
        return 2;
    }

    int camera_index = 0;
    if (argc == 2) {
        try {
            std::size_t parsed_characters = 0;
            camera_index = std::stoi(argv[1], &parsed_characters);
            if (parsed_characters != std::string(argv[1]).size() || camera_index < 0) {
                throw std::invalid_argument("invalid camera index");
            }
        } catch (const std::exception&) {
            std::cerr << "Camera index must be a non-negative integer.\n";
            return 2;
        }
    }

    cv::VideoCapture camera(camera_index, cv::CAP_V4L2);
    if (!camera.isOpened()) {
        std::cerr << "Could not open camera " << camera_index
                  << ". Check that it is connected and accessible.\n";
        return 1;
    }

    constexpr auto save_interval = std::chrono::milliseconds(500);
    auto next_save = std::chrono::steady_clock::now();
    cv::Mat frame;

    while (true) {
        if (!camera.read(frame) || frame.empty()) {
            std::cerr << "Failed to read a frame from camera " << camera_index << ".\n";
            camera.release();
            cv::destroyAllWindows();
            return 1;
        }

        cv::imshow("Pinhole Camera", frame);

        const auto now = std::chrono::steady_clock::now();
        if (now >= next_save) {
            if (!cv::imwrite("live.png", frame)) {
                std::cerr << "Could not save live.png.\n";
                camera.release();
                cv::destroyAllWindows();
                return 1;
            }
            next_save = now + save_interval;
        }

        const int key = cv::waitKey(1);
        if (key == 27 || key == 'q' || key == 'Q') {
            break;
        }
    }

    camera.release();
    cv::destroyAllWindows();
    return 0;
}