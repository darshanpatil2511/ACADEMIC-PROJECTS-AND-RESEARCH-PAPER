const mongoose = require("mongoose");

// Task Schema
const taskSchema = new mongoose.Schema(
    {
        name: {
            type: String,
            required: [true, "Task name is required"],
            trim: true,
            maxlength: [100, "Task name cannot exceed 100 characters"],
        },
        description: {
            type: String,
            required: [true, "Task description is required"],
            maxlength: [500, "Task description cannot exceed 500 characters"],
        },
        status: {
            type: String,
            enum: ["Available", "In Progress", "Completed", "Cancelled"],
            default: "Available",
        },
        priority: {
            type: String,
            enum: ["Low", "Medium", "High"],
            default: "Medium",
        },
        assignedTo: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "Volunteer",
            default: null,
        },
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "User",
            required: [true, "Task must be created by a valid user"],
        },
        dueDate: {
            type: Date,
            default: null,
            validate: {
                validator: function (v) {
                    return v === null || v > new Date();
                },
                message: "Due date must be in the future",
            },
        },
        tags: {
            type: [String],
            default: [],
        },
        category: {
            type: String,
            required: [true, "Task category is required"],
            trim: true,
        },
    },
    { timestamps: true }
);

// Static Methods for Query Optimization
taskSchema.statics.getTasksByStatus = async function (status) {
    return this.find({ status }).populate("assignedTo createdBy", "name email");
};

taskSchema.statics.getTasksByCategory = async function (category) {
    return this.find({ category }).populate("assignedTo createdBy", "name email");
};

// Middleware for Pre-save Validation
taskSchema.pre("save", function (next) {
    if (this.status === "Completed" && !this.assignedTo) {
        throw new Error("Completed tasks must have an assigned volunteer.");
    }
    next();
});

module.exports = mongoose.model("Task", taskSchema);
