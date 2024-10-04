//
//  AQueue.h
//  Pods
//
//  Created by Mark Gill on 10/3/24.
//
#ifndef CIRCULAR_BUFFER_H
#define CIRCULAR_BUFFER_H

#include <iostream>
#include <vector>


template <typename T>
class CircularBuffer {
public:
    CircularBuffer(size_t capacity) : capacity_(capacity), buffer_(capacity), head_(0), tail_(0), size_(0) {}

    void push_back(const T& value) {
        buffer_[tail_] = value;
        tail_ = (tail_ + 1) % capacity_;
        if (size_ < capacity_) {
            size_++;
        } else {
            if (overrun_count++ % 100000 == 0) {
                printf("CB: overrun: %zu\n", overrun_count);
            }
            // head_ = (head_ + 1) % capacity_;
        }
    }

    T pop_front() {
        if (empty()) {
            if (underrun_count++ % 100000 == 0) {
                printf("CB: overrun: %zu\n", underrun_count);
            }
            // printf("CB: underrun");
        }
        T value = buffer_[head_];
        head_ = (head_ + 1) % capacity_;
        size_--;
        return value;
    }

    bool empty() const {
        return size_ == 0;
    }

    size_t size() const {
        return size_;
    }

private:
    size_t capacity_;
    std::vector<T> buffer_;
    size_t head_;
    size_t tail_;
    size_t size_;
    size_t overrun_count=0;
    size_t underrun_count=0;
};

#endif /* AQueue_h */
