const mongoose = require("mongoose");
const bcrypt = require("bcrypt");

// User Schema
const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: [true, "Name is required"],
      trim: true,
      maxlength: [50, "Name cannot exceed 50 characters"],
    },
    email: {
      type: String,
      unique: true,
      required: [true, "Email is required"],
      trim: true,
      match: [
        /^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,3})+$/,
        "Please provide a valid email address",
      ],
    },
    password: {
      type: String,
      required: [true, "Password is required"],
      minlength: [6, "Password must be at least 6 characters long"],
    },
    role: {
      type: String,
      enum: ["admin", "volunteer", "customer"],
      default: "volunteer",
    },
    isActive: {
      type: Boolean,
      default: true, // Helps in managing deactivated accounts
    },
    lastLogin: {
      type: Date,
      default: null, // Tracks the last login time for the user
    },
  },
  { timestamps: true } // Automatically adds createdAt and updatedAt fields
);

// Pre-save middleware to hash the password before saving
userSchema.pre("save", async function (next) {
  if (!this.isModified("password")) return next(); // Skip if the password hasn't changed

  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to check if the provided password matches the hashed password
userSchema.methods.comparePassword = async function (candidatePassword) {
  try {
    return await bcrypt.compare(candidatePassword, this.password);
  } catch (error) {
    throw new Error("Error while comparing passwords");
  }
};

// Method to update the last login time
userSchema.methods.updateLastLogin = async function () {
  try {
    this.lastLogin = new Date();
    await this.save();
  } catch (error) {
    throw new Error("Error while updating last login time");
  }
};

// Static method to deactivate a user account
userSchema.statics.deactivateAccount = async function (userId) {
  try {
    const user = await this.findByIdAndUpdate(
      userId,
      { isActive: false },
      { new: true }
    );
    return user;
  } catch (error) {
    throw new Error("Error deactivating the account");
  }
};

// Static method to find active users
userSchema.statics.findActiveUsers = async function () {
  try {
    return await this.find({ isActive: true });
  } catch (error) {
    throw new Error("Error while fetching active users");
  }
};

module.exports = mongoose.model("User", userSchema);
