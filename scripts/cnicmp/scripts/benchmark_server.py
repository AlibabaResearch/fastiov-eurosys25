from flask import Flask, request, send_from_directory
import threading
import random
import os
import time
import logging

app = Flask(__name__)
app.logger.setLevel(logging.ERROR)

FILES_DIRECTORY = "/home/hdcni/cnicmp/scripts/benchmark_data/"

@app.route('/download/<filename>')
def download_file(filename):
    return send_from_directory(FILES_DIRECTORY, filename, as_attachment=True)


if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=False, threaded=True, processes=1, port=5100)