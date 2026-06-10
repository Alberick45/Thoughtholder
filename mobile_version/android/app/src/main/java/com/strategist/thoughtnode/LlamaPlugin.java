package com.strategist.thoughtnode;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@CapacitorPlugin(name = "Llama")
public class LlamaPlugin extends Plugin {

    // Cap thread usage to prevent mobile battery drain and thermal throttling
    // as per user specifications (2-4 threads).
    private static final int MAX_THREADS = 4;
    private ExecutorService executor = Executors.newFixedThreadPool(MAX_THREADS);

    // Mock state for llama.cpp context
    private boolean isModelLoaded = false;
    private String currentModelPath = "";

    @PluginMethod
    public void loadModel(PluginCall call) {
        String modelPath = call.getString("modelPath");
        if (modelPath == null) {
            call.reject("Must provide modelPath");
            return;
        }

        executor.submit(() -> {
            try {
                // TODO: Initialize llama.cpp JNI with the given GGUF model path
                // e.g. LlamaNative.loadModel(modelPath, MAX_THREADS);
                
                // Simulate loading delay
                Thread.sleep(1500);
                
                isModelLoaded = true;
                currentModelPath = modelPath;
                
                JSObject ret = new JSObject();
                ret.put("status", "loaded");
                ret.put("modelPath", modelPath);
                call.resolve(ret);
            } catch (Exception e) {
                call.reject("Failed to load model", e);
            }
        });
    }

    @PluginMethod(returnType = PluginMethod.RETURN_CALLBACK)
    public void generateTokenStream(PluginCall call) {
        if (!isModelLoaded) {
            call.reject("Model not loaded yet");
            return;
        }

        String prompt = call.getString("prompt");
        if (prompt == null) {
            call.reject("Must provide prompt");
            return;
        }
        
        // This keeps the callback open so we can stream tokens back
        call.setKeepAlive(true);

        executor.submit(() -> {
            try {
                // TODO: Call llama.cpp JNI to start inference
                // e.g. LlamaNative.generate(prompt, new TokenCallback() { ... });
                
                // Simulated token streaming
                String[] words = ("This is a simulated response from the native Llama engine. " +
                                  "It runs entirely offline using GGUF on Android.").split(" ");
                                  
                for (String word : words) {
                    Thread.sleep(50); // Simulate token generation time
                    JSObject ret = new JSObject();
                    ret.put("token", word + " ");
                    ret.put("done", false);
                    call.resolve(ret);
                }
                
                // Send final completion marker
                JSObject finalRet = new JSObject();
                finalRet.put("token", "");
                finalRet.put("done", true);
                call.resolve(finalRet);
                
            } catch (Exception e) {
                call.reject("Inference failed", e);
            } finally {
                // Close the callback once generation completes
                call.release(bridge);
            }
        });
    }
    
    @PluginMethod
    public void unloadModel(PluginCall call) {
        executor.submit(() -> {
            // TODO: Free llama.cpp JNI memory
            isModelLoaded = false;
            call.resolve();
        });
    }
}
