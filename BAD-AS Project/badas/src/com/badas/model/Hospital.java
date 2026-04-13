package com.badas.model;

public class Hospital {
    private int id;
    private String name;
    private String location;
    private int ambulanceCount;
    private int availableAmbulances;
    private String contact;
    private String createdAt;
    private String updatedAt;

    public Hospital() {}

    public Hospital(String name, String location, int ambulanceCount) {
        this.name = name;
        this.location = location;
        this.ambulanceCount = ambulanceCount;
        this.availableAmbulances = ambulanceCount;
    }

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }

    public int getAmbulanceCount() { return ambulanceCount; }
    public void setAmbulanceCount(int ambulanceCount) { this.ambulanceCount = ambulanceCount; }

    public int getAvailableAmbulances() { return availableAmbulances; }
    public void setAvailableAmbulances(int availableAmbulances) { this.availableAmbulances = availableAmbulances; }

    public String getContact() { return contact; }
    public void setContact(String contact) { this.contact = contact; }

    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }

    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }

    @Override
    public String toString() {
        return "Hospital{id=" + id + ", name='" + name + "', location='" + location + "'}";
    }
}
